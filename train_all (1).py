from __future__ import annotations

import argparse
import json
import os
import pickle
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Tuple

os.environ.setdefault("LOKY_MAX_CPU_COUNT", "1")

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier, IsolationForest
from sklearn.metrics import accuracy_score, f1_score, precision_score, recall_score, roc_auc_score
from sklearn.model_selection import GroupShuffleSplit
from sklearn.preprocessing import StandardScaler
from sklearn.utils.class_weight import compute_class_weight

try:
    from tensorflow.keras import Sequential
    from tensorflow.keras.callbacks import EarlyStopping
    from tensorflow.keras.layers import LSTM, Dense, Dropout, Input
    TENSORFLOW_AVAILABLE = True
except ImportError:  # pragma: no cover - depends on local environment
    Sequential = object
    EarlyStopping = None
    LSTM = Dense = Dropout = Input = None
    TENSORFLOW_AVAILABLE = False

try:
    from xgboost import XGBClassifier
    XGBOOST_AVAILABLE = True
    XGBOOST_IMPORT_ERROR = None
except Exception as exc:  # pragma: no cover - depends on local environment
    XGBClassifier = None
    XGBOOST_AVAILABLE = False
    XGBOOST_IMPORT_ERROR = exc

try:
    from .config import DATASET_PATH, FEATURE_NAMES, MODEL_DIR, NORMAL_RANGES, SEQUENCE_LENGTH
except ImportError:  # pragma: no cover - supports `python backend/train_all.py`
    from config import DATASET_PATH, FEATURE_NAMES, MODEL_DIR, NORMAL_RANGES, SEQUENCE_LENGTH


RANDOM_STATE = 42


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train ICU deterioration detection models.")
    parser.add_argument("--epochs", type=int, default=12, help="Number of epochs for the LSTM.")
    parser.add_argument("--batch-size", type=int, default=64, help="Training batch size for the LSTM.")
    parser.add_argument("--skip-lstm", action="store_true", help="Skip LSTM training when TensorFlow is unavailable.")
    return parser.parse_args()


def ensure_dirs() -> None:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)


def validate_dataset(df: pd.DataFrame) -> None:
    required_columns = {"Patient_ID", "Time", "Risk", *FEATURE_NAMES}
    missing = required_columns.difference(df.columns)
    if missing:
        raise ValueError(f"Dataset is missing required column(s): {sorted(missing)}")


def safe_roc_auc(y_true: np.ndarray, y_score: np.ndarray) -> float | None:
    if len(np.unique(y_true)) < 2:
        return None
    return float(roc_auc_score(y_true, y_score))


def metrics_from_scores(y_true: np.ndarray, y_prob: np.ndarray, threshold: float = 0.5) -> Dict[str, float | None]:
    y_pred = (y_prob >= threshold).astype(int)
    return {
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "f1": float(f1_score(y_true, y_pred, zero_division=0)),
        "roc_auc": safe_roc_auc(y_true, y_prob),
    }


def split_by_patient(df: pd.DataFrame) -> Tuple[pd.DataFrame, pd.DataFrame]:
    splitter = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=RANDOM_STATE)
    train_idx, test_idx = next(splitter.split(df, df["Risk"], groups=df["Patient_ID"]))
    train_df = df.iloc[train_idx].copy()
    test_df = df.iloc[test_idx].copy()
    return train_df, test_df


def create_sequences(df: pd.DataFrame, seq_length: int = SEQUENCE_LENGTH) -> Tuple[np.ndarray, np.ndarray]:
    sequences = []
    labels = []
    for patient_id, patient_df in df.groupby("Patient_ID"):
        patient_df = patient_df.sort_values("Time")
        values = patient_df[FEATURE_NAMES].to_numpy(dtype=np.float32)
        risks = patient_df["Risk"].to_numpy(dtype=np.int32)
        if len(patient_df) <= seq_length:
            continue
        for start in range(len(patient_df) - seq_length):
            stop = start + seq_length
            sequences.append(values[start:stop])
            labels.append(risks[stop])

    return np.array(sequences, dtype=np.float32), np.array(labels, dtype=np.int32)


def train_tabular_model(X_train: np.ndarray, y_train: np.ndarray) -> Tuple[object, str]:
    positives = int(y_train.sum())
    negatives = int(len(y_train) - positives)
    imbalance_weight = max(1.0, negatives / max(positives, 1))

    if XGBOOST_AVAILABLE:
        try:
            model = XGBClassifier(
                n_estimators=250,
                max_depth=4,
                learning_rate=0.05,
                subsample=0.9,
                colsample_bytree=0.9,
                objective="binary:logistic",
                eval_metric="logloss",
                random_state=RANDOM_STATE,
                scale_pos_weight=imbalance_weight,
            )
            model.fit(X_train, y_train)
            return model, "xgboost"
        except Exception as exc:
            print(f"XGBoost unavailable at runtime, falling back to HistGradientBoostingClassifier: {exc}")
    else:
        print(f"XGBoost import failed, falling back to HistGradientBoostingClassifier: {XGBOOST_IMPORT_ERROR}")

    model = HistGradientBoostingClassifier(
        learning_rate=0.05,
        max_depth=4,
        max_iter=250,
        random_state=RANDOM_STATE,
    )
    sample_weight = np.where(y_train == 1, imbalance_weight, 1.0)
    model.fit(X_train, y_train, sample_weight=sample_weight)
    return model, "hist_gradient_boosting"


def train_iso(X_train: np.ndarray, contamination: float) -> IsolationForest:
    model = IsolationForest(
        n_estimators=200,
        contamination=contamination,
        random_state=RANDOM_STATE,
        n_jobs=1,
    )
    model.fit(X_train)
    return model


def train_lstm(X_train: np.ndarray, y_train: np.ndarray, epochs: int, batch_size: int) -> Sequential:
    if not TENSORFLOW_AVAILABLE:
        raise RuntimeError("TensorFlow is not installed. Use Python 3.11/3.12 or pass --skip-lstm.")

    class_labels = np.unique(y_train)
    class_weights = compute_class_weight(class_weight="balanced", classes=class_labels, y=y_train)
    class_weight_map = {int(label): float(weight) for label, weight in zip(class_labels, class_weights)}

    model = Sequential(
        [
            Input(shape=(SEQUENCE_LENGTH, len(FEATURE_NAMES))),
            LSTM(64, return_sequences=True),
            Dropout(0.2),
            LSTM(32),
            Dense(32, activation="relu"),
            Dropout(0.2),
            Dense(1, activation="sigmoid"),
        ]
    )
    model.compile(loss="binary_crossentropy", optimizer="adam", metrics=["accuracy"])
    model.fit(
        X_train,
        y_train,
        epochs=epochs,
        batch_size=batch_size,
        validation_split=0.15,
        verbose=1,
        class_weight=class_weight_map,
        callbacks=[EarlyStopping(monitor="val_loss", patience=4, restore_best_weights=True)],
    )
    return model


def save_pickle(obj: object, path: Path) -> None:
    with path.open("wb") as handle:
        pickle.dump(obj, handle)


def main() -> None:
    args = parse_args()
    ensure_dirs()

    data = pd.read_csv(DATASET_PATH)
    validate_dataset(data)
    data = data.sort_values(by=["Patient_ID", "Time"]).reset_index(drop=True)

    train_df, test_df = split_by_patient(data)

    scaler = StandardScaler()
    train_df[FEATURE_NAMES] = scaler.fit_transform(train_df[FEATURE_NAMES])
    test_df[FEATURE_NAMES] = scaler.transform(test_df[FEATURE_NAMES])

    X_train = train_df[FEATURE_NAMES].to_numpy(dtype=np.float32)
    y_train = train_df["Risk"].to_numpy(dtype=np.int32)
    X_test = test_df[FEATURE_NAMES].to_numpy(dtype=np.float32)
    y_test = test_df["Risk"].to_numpy(dtype=np.int32)

    xgb, tabular_model_name = train_tabular_model(X_train, y_train)
    xgb_probs = xgb.predict_proba(X_test)[:, 1]
    xgb_metrics = metrics_from_scores(y_test, xgb_probs)

    contamination = float(np.clip(y_train.mean(), 0.05, 0.20))
    iso = train_iso(X_train, contamination=contamination)
    iso_anomaly_prob = 1.0 / (1.0 + np.exp(3.0 * iso.decision_function(X_test)))
    iso_metrics = metrics_from_scores(y_test, iso_anomaly_prob)

    lstm_metrics = None
    if args.skip_lstm:
        print("Skipping LSTM training because --skip-lstm was provided.")
    elif not TENSORFLOW_AVAILABLE:
        raise RuntimeError("TensorFlow is unavailable in this Python environment. Use Python 3.11 or 3.12, or rerun with --skip-lstm.")
    else:
        X_train_seq, y_train_seq = create_sequences(train_df)
        X_test_seq, y_test_seq = create_sequences(test_df)
        lstm = train_lstm(X_train_seq, y_train_seq, epochs=args.epochs, batch_size=args.batch_size)
        lstm_probs = lstm.predict(X_test_seq, verbose=0).reshape(-1)
        lstm_metrics = metrics_from_scores(y_test_seq, lstm_probs)
        lstm.save(MODEL_DIR / "lstm_timeseries.keras")
        lstm.save(MODEL_DIR / "lstm_timeseries.h5")

    save_pickle(scaler, MODEL_DIR / "scaler.pkl")
    save_pickle(xgb, MODEL_DIR / "xgb.pkl")
    save_pickle(iso, MODEL_DIR / "iso.pkl")

    metadata = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "dataset_path": str(DATASET_PATH),
        "row_count": int(len(data)),
        "patient_count": int(data["Patient_ID"].nunique()),
        "feature_names": FEATURE_NAMES,
        "sequence_length": SEQUENCE_LENGTH,
        "threshold_warning": 0.35,
        "threshold_critical": 0.65,
        "normal_ranges": NORMAL_RANGES,
        "training_summary": {
            "train_rows": int(len(train_df)),
            "test_rows": int(len(test_df)),
            "train_positive_rate": float(y_train.mean()),
            "test_positive_rate": float(y_test.mean()),
            "tensorflow_available": TENSORFLOW_AVAILABLE,
            "tabular_model": tabular_model_name,
            "xgb": xgb_metrics,
            "isolation_forest": iso_metrics,
            "lstm": lstm_metrics,
        },
    }
    (MODEL_DIR / "metadata.json").write_text(json.dumps(metadata, indent=2))

    print(json.dumps(metadata["training_summary"], indent=2))


if __name__ == "__main__":
    main()
