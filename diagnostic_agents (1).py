from __future__ import annotations

import json
import re
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

try:
    from .config import DATA_DIR, FEATURE_NAMES, NORMAL_RANGES
except ImportError:  # pragma: no cover - supports `python backend/app.py`
    from config import DATA_DIR, FEATURE_NAMES, NORMAL_RANGES


GUIDELINE_CORPUS_PATH = DATA_DIR / "medical_guidelines.json"
MONITORED_VITAL_KEYS = [*FEATURE_NAMES, "GCS"]

NOTE_SIGNAL_LIBRARY = [
    {
        "signal": "suspected infection",
        "severity": "warning",
        "risk_tags": ["sepsis", "screening"],
        "keywords": [
            "infection",
            "sepsis",
            "septic",
            "culture",
            "source",
            "febrile",
            "fever",
            "blood cultures",
        ],
        "summary": "Notes describe infection concern or an active sepsis workup.",
    },
    {
        "signal": "hemodynamic instability",
        "severity": "warning",
        "risk_tags": ["sepsis", "hypotension", "map"],
        "keywords": [
            "hypotension",
            "vasopressor",
            "pressor",
            "shock",
            "poor perfusion",
            "mottled",
        ],
        "summary": "Notes describe hypotension, shock, or perfusion concern.",
    },
    {
        "signal": "respiratory distress",
        "severity": "warning",
        "risk_tags": ["sepsis", "respiratory"],
        "keywords": [
            "tachypne",
            "desat",
            "spo2",
            "oxygen",
            "hypoxia",
            "airway",
            "respiratory distress",
        ],
        "summary": "Notes describe oxygenation decline or respiratory distress.",
    },
    {
        "signal": "mental status change",
        "severity": "warning",
        "risk_tags": ["sepsis", "neurologic"],
        "keywords": [
            "confus",
            "drowsy",
            "altered",
            "delir",
            "gcs",
            "letharg",
            "encephal",
        ],
        "summary": "Notes describe confusion, drowsiness, or altered neurologic state.",
    },
    {
        "signal": "renal concern",
        "severity": "warning",
        "risk_tags": ["acute_kidney_injury", "renal_failure"],
        "keywords": [
            "oliguria",
            "urine output",
            "creatinine",
            "renal",
            "aki",
        ],
        "summary": "Notes describe falling urine output or renal dysfunction concern.",
    },
]

LAB_ALIASES = {
    "wbc": ["wbc", "white blood cell", "white blood cells", "white count"],
    "lactate": ["lactate", "serum lactate"],
    "creatinine": ["creatinine", "serum creatinine", "scr"],
}

LAB_THRESHOLDS = {
    "wbc": {
        "label": "WBC",
        "warning_low": 4.0,
        "warning_high": 12.0,
        "critical_high": 20.0,
        "risk_tags": ["sepsis", "infection"],
    },
    "lactate": {
        "label": "Lactate",
        "warning_high": 2.0,
        "critical_high": 4.0,
        "risk_tags": ["sepsis", "hypoperfusion", "lactate"],
    },
    "creatinine": {
        "label": "Creatinine",
        "warning_high": 1.2,
        "critical_high": 2.0,
        "delta_warning": 0.3,
        "ratio_warning": 1.5,
        "risk_tags": ["acute_kidney_injury", "creatinine", "organ_failure"],
    },
}

LAB_OUTLIER_TOLERANCE = {
    "wbc": 1.5,
    "lactate": 0.6,
    "creatinine": 0.2,
}


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _tokenize(text: str) -> set[str]:
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def _sort_key(timestamp: Any, fallback_index: int) -> float:
    if isinstance(timestamp, (int, float)):
        return float(timestamp)

    text = str(timestamp or "").strip()
    if not text:
        return float(fallback_index)

    try:
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        try:
            return float(text)
        except ValueError:
            return float(fallback_index)


def _severity_rank(label: str) -> int:
    return {"normal": 0, "warning": 1, "high": 2, "critical": 3}.get(label.lower(), 0)


def _risk_level_from_score(score: float) -> str:
    if score >= 0.85:
        return "CRITICAL"
    if score >= 0.65:
        return "HIGH"
    if score >= 0.35:
        return "MODERATE"
    return "LOW"


def _normalize_lab_name(name: Any) -> str:
    normalized = re.sub(r"[^a-z0-9]+", " ", str(name or "").lower()).strip()
    for canonical, aliases in LAB_ALIASES.items():
        if normalized == canonical or any(alias in normalized for alias in aliases):
            return canonical
    return normalized.replace(" ", "_") or "unknown_lab"


def _trim_text(text: str, limit: int = 160) -> str:
    collapsed = " ".join(text.split())
    if len(collapsed) <= limit:
        return collapsed
    return f"{collapsed[: limit - 1].rstrip()}..."


class NoteParserAgent:
    role = "Note Parser Agent"

    def analyze(self, notes: List[Dict[str, Any]]) -> Dict[str, Any]:
        matched_signals: List[Dict[str, Any]] = []
        timeline_events: List[Dict[str, Any]] = []
        risk_tags: Counter[str] = Counter()
        evidence: List[str] = []

        for index, note in enumerate(notes):
            text = str(note.get("text") or note.get("note") or "").strip()
            author = str(note.get("author") or "Unknown clinician")
            specialty = str(note.get("specialty") or note.get("service") or "Unknown service")
            timestamp = str(note.get("timestamp") or note.get("time") or _utc_now())
            sort_key = _sort_key(timestamp, index)
            local_matches = []

            for signal in NOTE_SIGNAL_LIBRARY:
                if any(keyword in text.lower() for keyword in signal["keywords"]):
                    local_matches.append(signal["signal"])
                    matched_signals.append(
                        {
                            "timestamp": timestamp,
                            "author": author,
                            "signal": signal["signal"],
                            "severity": signal["severity"],
                            "summary": signal["summary"],
                        }
                    )
                    risk_tags.update(signal["risk_tags"])
                    evidence.append(f"{author} note mentions {signal['signal']}.")

            summary = _trim_text(text) if text else "No note text supplied."
            timeline_events.append(
                {
                    "timestamp": timestamp,
                    "sort_key": sort_key,
                    "source": "note",
                    "severity": "warning" if local_matches else "normal",
                    "summary": f"{author} ({specialty}) documented: {summary}",
                }
            )

        return {
            "agent_role": self.role,
            "note_count": len(notes),
            "matched_signals": matched_signals,
            "risk_tag_counts": dict(risk_tags),
            "evidence": evidence,
            "timeline_events": timeline_events,
            "summary": "Parsed note history for infectious, respiratory, neurologic, hemodynamic, and renal cues.",
        }


class TemporalLabMapperAgent:
    role = "Temporal Lab Mapper Agent"

    def analyze(self, labs: List[Dict[str, Any]]) -> Dict[str, Any]:
        series_by_lab: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        timeline_events: List[Dict[str, Any]] = []
        trend_summaries: Dict[str, Dict[str, Any]] = {}
        evidence: List[str] = []
        risk_tags: Counter[str] = Counter()

        for index, lab in enumerate(labs):
            timestamp = str(lab.get("timestamp") or lab.get("time") or _utc_now())
            sort_key = _sort_key(timestamp, index)
            name = _normalize_lab_name(lab.get("name") or lab.get("lab") or lab.get("test"))
            label = LAB_THRESHOLDS.get(name, {}).get("label", str(lab.get("name") or name).upper())
            value = float(lab.get("value"))
            unit = str(lab.get("unit") or "")
            redraw_confirmed = bool(lab.get("confirmed_redraw") or lab.get("redraw_confirmed"))
            unit_suffix = f" {unit}" if unit else ""
            entry = {
                "timestamp": timestamp,
                "sort_key": sort_key,
                "name": name,
                "label": label,
                "value": value,
                "unit": unit,
                "confirmed_redraw": redraw_confirmed,
            }
            series_by_lab[name].append(entry)
            timeline_events.append(
                {
                    "timestamp": timestamp,
                    "sort_key": sort_key,
                    "source": "lab",
                    "severity": "normal",
                    "summary": f"{label} measured at {value:.2f}{unit_suffix}.",
                }
            )

        for lab_name, series in series_by_lab.items():
            series.sort(key=lambda item: item["sort_key"])
            latest = series[-1]
            previous = series[-2] if len(series) > 1 else None
            delta = latest["value"] - previous["value"] if previous else None
            trend = "stable"
            if delta is not None:
                if delta > 0.05:
                    trend = "rising"
                elif delta < -0.05:
                    trend = "falling"

            threshold = LAB_THRESHOLDS.get(lab_name, {})
            risk_level = "normal"
            if lab_name == "wbc" and (latest["value"] < threshold.get("warning_low", -1) or latest["value"] > threshold.get("warning_high", 10**9)):
                risk_level = "warning"
            if lab_name in {"lactate", "creatinine"} and latest["value"] >= threshold.get("warning_high", 10**9):
                risk_level = "warning"
            if latest["value"] >= threshold.get("critical_high", 10**9):
                risk_level = "critical"

            if risk_level != "normal":
                risk_tags.update(threshold.get("risk_tags", []))
                latest_unit_suffix = f" {latest['unit']}" if latest["unit"] else ""
                evidence.append(
                    f"{latest['label']} is {latest['value']:.2f}{latest_unit_suffix} and trending {trend}."
                )

            trend_summaries[lab_name] = {
                "label": latest["label"],
                "latest_value": round(latest["value"], 4),
                "unit": latest["unit"],
                "trend": trend,
                "delta_from_previous": None if delta is None else round(delta, 4),
                "points": len(series),
                "series": [
                    {
                        "timestamp": item["timestamp"],
                        "value": round(item["value"], 4),
                        "unit": item["unit"],
                        "confirmed_redraw": item["confirmed_redraw"],
                    }
                    for item in series
                ],
            }

        return {
            "agent_role": self.role,
            "lab_count": len(labs),
            "trend_summaries": trend_summaries,
            "series_by_lab": dict(series_by_lab),
            "risk_tag_counts": dict(risk_tags),
            "evidence": evidence,
            "timeline_events": timeline_events,
            "summary": "Mapped lab values into chronological series and computed trend deltas.",
        }


class GuidelineRAGAgent:
    role = "Guideline RAG Agent"

    def __init__(self, corpus_path: Path | None = None) -> None:
        self.corpus_path = corpus_path or GUIDELINE_CORPUS_PATH
        self.corpus = self._load_corpus()

    def _load_corpus(self) -> List[Dict[str, Any]]:
        if not self.corpus_path.exists():
            return []
        return json.loads(self.corpus_path.read_text())

    def retrieve(self, topics: Iterable[str], evidence: Iterable[str], limit: int = 3) -> List[Dict[str, Any]]:
        topic_tokens = set()
        for topic in topics:
            topic_tokens.update(_tokenize(str(topic)))

        evidence_tokens = set()
        for item in evidence:
            evidence_tokens.update(_tokenize(str(item)))

        query_tokens = topic_tokens | evidence_tokens
        scored: List[Tuple[int, Dict[str, Any]]] = []

        for entry in self.corpus:
            entry_topics = set(entry.get("topics", []))
            entry_tokens = _tokenize(
                " ".join(entry.get("topics", []))
                + " "
                + " ".join(entry.get("keywords", []))
                + " "
                + str(entry.get("summary", ""))
                + " "
                + " ".join(entry.get("support_points", []))
            )
            overlap = query_tokens & entry_tokens
            topic_overlap = len(topic_tokens & _tokenize(" ".join(entry_topics)))
            score = len(overlap) + (topic_overlap * 3)
            if score == 0:
                continue
            scored.append(
                (
                    score,
                    {
                        "id": entry["id"],
                        "title": entry["title"],
                        "organization": entry["organization"],
                        "year": entry["year"],
                        "url": entry["url"],
                        "summary": entry["summary"],
                        "support_points": entry["support_points"],
                        "matched_terms": sorted(overlap)[:8],
                        "retrieval_score": score,
                    },
                )
            )

        scored.sort(key=lambda item: item[0], reverse=True)
        return [item[1] for item in scored[:limit]]


class ChiefSynthesisAgent:
    role = "Chief Synthesis Agent"

    def synthesize(
        self,
        patient_id: str,
        vitals: List[Dict[str, Any]],
        latest_features: Dict[str, float],
        note_output: Dict[str, Any],
        lab_output: Dict[str, Any],
        rag_agent: GuidelineRAGAgent,
        ml_assessment: Dict[str, Any] | None,
    ) -> Dict[str, Any]:
        probable_lab_errors, filtered_series = self._detect_probable_lab_errors(lab_output["series_by_lab"])

        flagged_risks: List[Dict[str, Any]] = []
        sepsis_flag = self._build_sepsis_flag(
            latest_features=latest_features,
            note_output=note_output,
            filtered_series=filtered_series,
            rag_agent=rag_agent,
            ml_assessment=ml_assessment,
        )
        if sepsis_flag is not None:
            flagged_risks.append(sepsis_flag)

        aki_flag = self._build_aki_flag(
            latest_features=latest_features,
            note_output=note_output,
            filtered_series=filtered_series,
            probable_lab_errors=probable_lab_errors,
            rag_agent=rag_agent,
            ml_assessment=ml_assessment,
        )
        if aki_flag is not None:
            flagged_risks.append(aki_flag)

        all_citations: Dict[str, Dict[str, Any]] = {}
        for risk in flagged_risks:
            for citation in risk["guideline_citations"]:
                all_citations[citation["id"]] = citation

        timeline = self._build_timeline(
            vitals=vitals,
            notes=note_output["timeline_events"],
            labs=lab_output["timeline_events"],
            probable_lab_errors=probable_lab_errors,
        )
        recommended_actions = self._merge_actions(flagged_risks, probable_lab_errors, ml_assessment)
        overall_level = self._overall_level(flagged_risks, ml_assessment)
        primary_concern = flagged_risks[0]["title"] if flagged_risks else "No high-confidence deterioration flag"
        chief_summary = self._chief_summary(patient_id, flagged_risks, probable_lab_errors, ml_assessment)
        probability = self._report_probability(flagged_risks, ml_assessment)
        timeline_by_day = self._group_timeline_by_day(timeline)
        explainability = self._build_explainability(
            latest_features=latest_features,
            filtered_series=filtered_series,
            flagged_risks=flagged_risks,
            ml_assessment=ml_assessment,
        )
        handoff_summary = self._build_handoff_summary(
            patient_id=patient_id,
            overall_level=overall_level,
            primary_concern=primary_concern,
            flagged_risks=flagged_risks,
            probable_lab_errors=probable_lab_errors,
            recommended_actions=recommended_actions,
        )
        diagnostic_risk_report = {
            "risk_level": overall_level,
            "probability": probability,
            "early_warning": [risk["title"] for risk in flagged_risks],
            "evidence": self._flatten_evidence(flagged_risks, ml_assessment),
            "guidelines": [
                f"{citation['title']} ({citation['organization']}, {citation['year']})"
                for citation in all_citations.values()
            ],
            "outliers": [error["reason"] for error in probable_lab_errors],
            "safety_note": (
                "This is decision support only. It must not be used as an autonomous diagnosis."
            ),
            "shift_handoff_summary": handoff_summary,
            "explainability": explainability,
        }

        return {
            "agent_role": self.role,
            "patient_id": patient_id,
            "generated_at": _utc_now(),
            "safety_caveat": (
                "Decision-support only. This report is not a clinical diagnosis. "
                "A licensed clinician must verify the patient, confirm critical labs, and review the full chart before treatment changes."
            ),
            "overall_risk_level": overall_level,
            "primary_concern": primary_concern,
            "chief_summary": chief_summary,
            "diagnosis_update_blocked": bool(probable_lab_errors),
            "probable_lab_errors": probable_lab_errors,
            "flagged_risks": flagged_risks,
            "recommended_actions": recommended_actions,
            "disease_progression_timeline": timeline,
            "disease_progression_timeline_by_day": timeline_by_day,
            "guideline_citations": list(all_citations.values()),
            "latest_vitals": latest_features,
            "current_ml_risk": ml_assessment,
            "shift_handoff_summary": handoff_summary,
            "diagnostic_risk_report": diagnostic_risk_report,
            "explainability": explainability,
        }

    def _detect_probable_lab_errors(
        self, series_by_lab: Dict[str, List[Dict[str, Any]]]
    ) -> Tuple[List[Dict[str, Any]], Dict[str, List[Dict[str, Any]]]]:
        probable_errors: List[Dict[str, Any]] = []
        filtered_series: Dict[str, List[Dict[str, Any]]] = {}

        for lab_name, series in series_by_lab.items():
            if len(series) < 4:
                filtered_series[lab_name] = list(series)
                continue

            latest = series[-1]
            if latest.get("confirmed_redraw"):
                filtered_series[lab_name] = list(series)
                continue

            previous_window = series[-4:-1]
            previous_values = [float(item["value"]) for item in previous_window]
            median_value = statistics.median(previous_values)
            stable_spread = max(previous_values) - min(previous_values)
            tolerance = LAB_OUTLIER_TOLERANCE.get(lab_name, max(abs(median_value) * 0.15, 0.5))
            mad = statistics.median(abs(value - median_value) for value in previous_values)
            scale = max(1.4826 * mad, tolerance)
            robust_deviation = abs(float(latest["value"]) - median_value) / scale
            relative_shift = abs(float(latest["value"]) - median_value) / max(abs(median_value), 1.0)

            if stable_spread <= tolerance and robust_deviation >= 4.5 and relative_shift >= 0.6:
                probable_errors.append(
                    {
                        "lab_name": latest["label"],
                        "timestamp": latest["timestamp"],
                        "latest_value": round(float(latest["value"]), 4),
                        "unit": latest["unit"],
                        "historical_values": [round(value, 4) for value in previous_values],
                        "historical_median": round(float(median_value), 4),
                        "detection_method": "robust_z_score + temporal_consistency",
                        "robust_z_score": round(float(robust_deviation), 2),
                        "relative_shift_ratio": round(float(relative_shift), 2),
                        "temporal_window_points": len(previous_values),
                        "reason": (
                            f"{latest['label']} is sharply discordant with three prior stable values and is being treated as a probable lab error."
                        ),
                        "action": "Hold diagnosis escalation from this lab result until a confirmed redraw is available.",
                    }
                )
                filtered_series[lab_name] = list(series[:-1])
            else:
                filtered_series[lab_name] = list(series)

        return probable_errors, filtered_series

    def _build_sepsis_flag(
        self,
        latest_features: Dict[str, float],
        note_output: Dict[str, Any],
        filtered_series: Dict[str, List[Dict[str, Any]]],
        rag_agent: GuidelineRAGAgent,
        ml_assessment: Dict[str, Any] | None,
    ) -> Dict[str, Any] | None:
        score = 0.0
        evidence: List[str] = []
        topics = ["sepsis", "lactate", "map", "screening"]
        risk_counts = note_output.get("risk_tag_counts", {})

        if risk_counts.get("sepsis", 0):
            score += 0.18
            evidence.append("Clinical notes mention infection concern or active sepsis evaluation.")

        temperature = latest_features.get("Temp")
        if temperature is not None and (temperature >= 38.0 or temperature <= 36.0):
            score += 0.12
            evidence.append(f"Temperature is abnormal at {temperature:.1f} C.")

        heart_rate = latest_features.get("HR")
        if heart_rate is not None and heart_rate >= 100:
            score += 0.08
            evidence.append(f"Heart rate is elevated at {heart_rate:.0f} bpm.")

        respiratory_rate = latest_features.get("Resp")
        if respiratory_rate is not None and respiratory_rate >= 22:
            score += 0.08
            evidence.append(f"Respiratory rate is elevated at {respiratory_rate:.0f}/min.")

        systolic_bp = latest_features.get("BP_sys")
        diastolic_bp = latest_features.get("BP_dia")
        if systolic_bp is not None and diastolic_bp is not None:
            map_value = (systolic_bp + (2 * diastolic_bp)) / 3
            if systolic_bp < 90 or map_value < 65:
                score += 0.16
                evidence.append(f"Perfusion is concerning with BP {systolic_bp:.0f}/{diastolic_bp:.0f} and MAP {map_value:.0f}.")

        gcs = latest_features.get("GCS")
        if gcs is not None and gcs < 15:
            score += 0.06
            evidence.append(f"GCS has declined to {gcs:.0f}/15.")

        wbc_series = filtered_series.get("wbc", [])
        if wbc_series:
            latest_wbc = wbc_series[-1]["value"]
            if latest_wbc < 4.0 or latest_wbc > 12.0:
                score += 0.08
                evidence.append(f"WBC is abnormal at {latest_wbc:.1f} K/uL.")

        lactate_series = filtered_series.get("lactate", [])
        if lactate_series:
            latest_lactate = lactate_series[-1]["value"]
            if latest_lactate >= 2.0:
                score += 0.14 if latest_lactate < 4.0 else 0.22
                evidence.append(f"Lactate is elevated at {latest_lactate:.1f} mmol/L.")

        if ml_assessment is not None:
            model_score = float(ml_assessment.get("risk_score", 0.0))
            score += 0.22 * model_score
            evidence.append(f"Physiology model risk score is {model_score:.2f}.")

        score = round(clamp(score), 4)
        if score < 0.35 and len(evidence) < 3:
            return None

        citations = rag_agent.retrieve(topics=topics, evidence=evidence, limit=2)
        return {
            "title": "Early sepsis risk",
            "level": _risk_level_from_score(score),
            "score": score,
            "summary": "Combined vitals, labs, and notes show a sepsis-like deterioration pattern.",
            "supporting_evidence": evidence,
            "guideline_citations": citations,
        }

    def _build_aki_flag(
        self,
        latest_features: Dict[str, float],
        note_output: Dict[str, Any],
        filtered_series: Dict[str, List[Dict[str, Any]]],
        probable_lab_errors: List[Dict[str, Any]],
        rag_agent: GuidelineRAGAgent,
        ml_assessment: Dict[str, Any] | None,
    ) -> Dict[str, Any] | None:
        creatinine_series = filtered_series.get("creatinine", [])
        note_counts = note_output.get("risk_tag_counts", {})
        evidence: List[str] = []
        score = 0.0

        if note_counts.get("acute_kidney_injury", 0) or note_counts.get("renal_failure", 0):
            score += 0.18
            evidence.append("Clinical notes mention oliguria or renal concern.")

        if probable_lab_errors:
            evidence.append("A conflicting latest lab value was withheld from diagnosis updates until redraw.")

        if len(creatinine_series) >= 2:
            latest_creatinine = float(creatinine_series[-1]["value"])
            baseline_creatinine = min(float(item["value"]) for item in creatinine_series[:-1]) if len(creatinine_series) > 1 else latest_creatinine
            previous_creatinine = float(creatinine_series[-2]["value"])
            absolute_delta = latest_creatinine - previous_creatinine
            baseline_ratio = latest_creatinine / max(baseline_creatinine, 0.1)

            if absolute_delta >= 0.3:
                score += 0.30
                evidence.append(f"Creatinine increased by {absolute_delta:.2f} mg/dL compared with the prior result.")
            if baseline_ratio >= 1.5:
                score += 0.28
                evidence.append(f"Creatinine is {baseline_ratio:.2f}x the recent baseline.")

        systolic_bp = latest_features.get("BP_sys")
        if systolic_bp is not None and systolic_bp < 90:
            score += 0.10
            evidence.append(f"Hypotension is present with systolic pressure {systolic_bp:.0f} mmHg.")

        if ml_assessment is not None and float(ml_assessment.get("risk_score", 0.0)) >= 0.65:
            score += 0.06
            evidence.append("Global physiology model is already in a high-risk band.")

        score = round(clamp(score), 4)
        if score < 0.35 and len(evidence) < 2:
            return None

        citations = rag_agent.retrieve(
            topics=["acute_kidney_injury", "creatinine", "oliguria"],
            evidence=evidence,
            limit=2,
        )
        return {
            "title": "Organ failure / AKI risk",
            "level": _risk_level_from_score(score),
            "score": score,
            "summary": "Renal trend review suggests possible evolving AKI, while isolated contradictory labs remain blocked pending redraw.",
            "supporting_evidence": evidence,
            "guideline_citations": citations,
        }

    def _build_timeline(
        self,
        vitals: List[Dict[str, Any]],
        notes: List[Dict[str, Any]],
        labs: List[Dict[str, Any]],
        probable_lab_errors: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        events: List[Dict[str, Any]] = []

        for index, snapshot in enumerate(vitals):
            features = snapshot["features"]
            timestamp = snapshot["timestamp"]
            sort_key = snapshot["sort_key"]
            abnormalities = []
            for feature_name, value in features.items():
                reference = NORMAL_RANGES.get(feature_name)
                if reference is None:
                    continue
                if feature_name == "SpO2":
                    if value < reference["normal_low"]:
                        abnormalities.append(f"{feature_name} {value:.0f}")
                elif feature_name == "GCS":
                    if value < reference["normal_low"]:
                        abnormalities.append(f"{feature_name} {value:.0f}")
                elif value < reference["normal_low"] or value > reference["normal_high"]:
                    abnormalities.append(f"{feature_name} {value:.1f}")

            summary = "Vitals remained within the monitored range."
            severity = "normal"
            if abnormalities:
                severity = "warning"
                summary = f"Vital shift detected: {', '.join(abnormalities[:4])}."

            if index == len(vitals) - 1:
                severity = "high" if abnormalities else severity
                summary = f"Latest bedside snapshot: {', '.join(f'{key} {value:.1f}' for key, value in features.items())}."

            events.append(
                {
                    "timestamp": timestamp,
                    "sort_key": sort_key,
                    "source": "vitals",
                    "severity": severity,
                    "summary": summary,
                }
            )

        events.extend(notes)
        events.extend(labs)

        for error in probable_lab_errors:
            events.append(
                {
                    "timestamp": error["timestamp"],
                    "sort_key": _sort_key(error["timestamp"], len(events)),
                    "source": "lab_error_guard",
                    "severity": "high",
                    "summary": error["reason"],
                }
            )

        events.sort(key=lambda item: item["sort_key"])
        return [
            {
                "timestamp": event["timestamp"],
                "source": event["source"],
                "severity": event["severity"],
                "summary": event["summary"],
            }
            for event in events[-14:]
        ]

    @staticmethod
    def _merge_actions(
        flagged_risks: List[Dict[str, Any]],
        probable_lab_errors: List[Dict[str, Any]],
        ml_assessment: Dict[str, Any] | None,
    ) -> List[str]:
        actions: List[str] = []
        if ml_assessment is not None:
            for action in ml_assessment.get("recommended_actions", []):
                if action not in actions:
                    actions.append(action)

        for risk in flagged_risks:
            if "sepsis" in risk["title"].lower():
                actions.extend(
                    [
                        "Reassess infection source, perfusion, lactate trend, and escalation timing immediately.",
                        "Review cultures, antibiotics, and MAP support while repeating bedside evaluation.",
                    ]
                )
            if "aki" in risk["title"].lower() or "organ failure" in risk["title"].lower():
                actions.extend(
                    [
                        "Review urine output, baseline creatinine, nephrotoxic exposures, and perfusion status.",
                    ]
                )

        if probable_lab_errors:
            actions.append("Repeat the discordant lab on an urgent redraw before changing diagnosis based on that result.")

        deduped: List[str] = []
        for action in actions:
            if action not in deduped:
                deduped.append(action)
        return deduped[:8]

    @staticmethod
    def _report_probability(flagged_risks: List[Dict[str, Any]], ml_assessment: Dict[str, Any] | None) -> float:
        scores = [float(risk["score"]) for risk in flagged_risks]
        if ml_assessment is not None:
            scores.append(float(ml_assessment.get("risk_score", 0.0)))
        return round(max(scores or [0.0]), 4)

    @staticmethod
    def _flatten_evidence(flagged_risks: List[Dict[str, Any]], ml_assessment: Dict[str, Any] | None) -> List[str]:
        evidence: List[str] = []
        for risk in flagged_risks:
            for item in risk.get("supporting_evidence", []):
                if item not in evidence:
                    evidence.append(item)
        if ml_assessment is not None:
            for item in ml_assessment.get("top_reasons", []):
                if item not in evidence:
                    evidence.append(item)
        return evidence[:8]

    @staticmethod
    def _group_timeline_by_day(timeline: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        grouped: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        ordered_dates: List[str] = []
        for event in timeline:
            timestamp = str(event["timestamp"])
            date_key = timestamp.split("T")[0] if "T" in timestamp else timestamp
            if date_key not in grouped:
                ordered_dates.append(date_key)
            grouped[date_key].append(event)

        grouped_days: List[Dict[str, Any]] = []
        for index, date_key in enumerate(ordered_dates, start=1):
            grouped_days.append(
                {
                    "day_label": f"Day {index}",
                    "date": date_key,
                    "events": grouped[date_key],
                }
            )
        return grouped_days

    def _build_explainability(
        self,
        latest_features: Dict[str, float],
        filtered_series: Dict[str, List[Dict[str, Any]]],
        flagged_risks: List[Dict[str, Any]],
        ml_assessment: Dict[str, Any] | None,
    ) -> Dict[str, Any]:
        contributors: List[Dict[str, Any]] = []
        for feature_name, value in latest_features.items():
            reference = NORMAL_RANGES.get(feature_name)
            if reference is None:
                continue

            deviation = 0.0
            if feature_name in {"SpO2", "GCS"}:
                if value < reference["normal_low"]:
                    span = max(reference["normal_low"] - reference["critical_low"], 1.0)
                    deviation = (reference["normal_low"] - value) / span
            elif value < reference["normal_low"]:
                span = max(reference["normal_low"] - reference["critical_low"], 1.0)
                deviation = (reference["normal_low"] - value) / span
            elif value > reference["normal_high"]:
                span = max(reference["critical_high"] - reference["normal_high"], 1.0)
                deviation = (value - reference["normal_high"]) / span

            if deviation <= 0:
                continue

            contributors.append(
                {
                    "feature": feature_name,
                    "value": round(float(value), 4),
                    "impact_score": round(clamp(deviation), 4),
                    "reason": f"{feature_name} is outside the monitored normal range.",
                }
            )

        lab_reason_map = {
            "wbc": "WBC trend is abnormal across the recent timeline.",
            "lactate": "Lactate trend supports hypoperfusion or evolving sepsis.",
            "creatinine": "Creatinine trend suggests renal stress or possible AKI.",
        }
        for lab_name, series in filtered_series.items():
            if not series:
                continue
            latest_value = float(series[-1]["value"])
            threshold = LAB_THRESHOLDS.get(lab_name)
            if threshold is None:
                continue
            impact = 0.0
            if lab_name == "wbc" and (latest_value < threshold["warning_low"] or latest_value > threshold["warning_high"]):
                impact = 0.55
            elif latest_value >= threshold.get("critical_high", 10**9):
                impact = 0.85
            elif latest_value >= threshold.get("warning_high", 10**9):
                impact = 0.65

            if impact > 0:
                contributors.append(
                    {
                        "feature": threshold["label"],
                        "value": round(latest_value, 4),
                        "impact_score": round(impact, 4),
                        "reason": lab_reason_map.get(lab_name, "Lab value is abnormal."),
                    }
                )

        contributors.sort(key=lambda item: float(item["impact_score"]), reverse=True)
        top_contributors = contributors[:6]
        top_labels = [item["feature"] for item in top_contributors[:3]]
        narrative = (
            f"The main local contributors were {', '.join(top_labels)}."
            if top_labels
            else "No major abnormal contributors were detected in the latest snapshot."
        )

        return {
            "method": "Local feature contribution summary over abnormal vitals, lab trends, and model components.",
            "top_contributors": top_contributors,
            "model_components": {} if ml_assessment is None else ml_assessment.get("component_scores", {}),
            "flag_count": len(flagged_risks),
            "narrative": narrative,
        }

    @staticmethod
    def _build_handoff_summary(
        patient_id: str,
        overall_level: str,
        primary_concern: str,
        flagged_risks: List[Dict[str, Any]],
        probable_lab_errors: List[Dict[str, Any]],
        recommended_actions: List[str],
    ) -> str:
        warnings = ", ".join(risk["title"] for risk in flagged_risks[:2]) or "no major syndrome flags"
        next_action = recommended_actions[0] if recommended_actions else "continue clinical review"
        summary = (
            f"Handoff summary for {patient_id}: overall risk is {overall_level.lower()} with primary concern '{primary_concern}'. "
            f"Current warnings include {warnings}. Next step: {next_action}."
        )
        if probable_lab_errors:
            summary += " A contradictory lab was quarantined pending redraw confirmation."
        return summary

    @staticmethod
    def _overall_level(flagged_risks: List[Dict[str, Any]], ml_assessment: Dict[str, Any] | None) -> str:
        levels = [_severity_rank(risk["level"].lower()) for risk in flagged_risks]
        if ml_assessment is not None:
            levels.append(_severity_rank(_risk_level_from_score(float(ml_assessment.get("risk_score", 0.0))).lower()))
        max_level = max(levels or [0])
        return {0: "LOW", 1: "MODERATE", 2: "HIGH", 3: "CRITICAL"}[max_level]

    @staticmethod
    def _chief_summary(
        patient_id: str,
        flagged_risks: List[Dict[str, Any]],
        probable_lab_errors: List[Dict[str, Any]],
        ml_assessment: Dict[str, Any] | None,
    ) -> str:
        if flagged_risks:
            lead = flagged_risks[0]
            summary = f"{patient_id} shows {lead['title'].lower()} at {lead['level'].lower()} confidence."
        else:
            summary = f"{patient_id} has no high-confidence syndrome flag from the multi-agent review."

        if ml_assessment is not None:
            summary += f" Current physiology model risk is {float(ml_assessment.get('risk_score', 0.0)):.2f}."

        if probable_lab_errors:
            summary += " At least one contradictory lab result was blocked as a probable error until redraw confirmation."

        return summary


class MultiAgentDiagnosticEngine:
    def __init__(self, risk_agent: Any | None = None) -> None:
        self.risk_agent = risk_agent
        self.note_agent = NoteParserAgent()
        self.lab_agent = TemporalLabMapperAgent()
        self.rag_agent = GuidelineRAGAgent()
        self.chief_agent = ChiefSynthesisAgent()

    def run(self, payload: Any) -> Dict[str, Any]:
        if not isinstance(payload, dict):
            raise ValueError("Diagnostic report payload must be a JSON object.")

        patient_id = str(payload.get("patient_id") or payload.get("Patient_ID") or "UNKNOWN")
        notes = self._normalize_notes(payload.get("notes", []))
        labs = self._normalize_labs(payload.get("labs", []))
        vitals = self._normalize_vitals(payload)
        latest_features = vitals[-1]["features"] if vitals else {}

        note_output = self.note_agent.analyze(notes)
        lab_output = self.lab_agent.analyze(labs)
        ml_assessment = self._run_risk_agent(patient_id, latest_features, vitals[-1]["timestamp"] if vitals else _utc_now())
        chief_output = self.chief_agent.synthesize(
            patient_id=patient_id,
            vitals=vitals,
            latest_features=latest_features,
            note_output=note_output,
            lab_output=lab_output,
            rag_agent=self.rag_agent,
            ml_assessment=ml_assessment,
        )

        return {
            "patient_id": patient_id,
            "generated_at": chief_output["generated_at"],
            "safety_caveat": chief_output["safety_caveat"],
            "agents": {
                "note_parser_agent": note_output,
                "temporal_lab_mapper_agent": {
                    key: value
                    for key, value in lab_output.items()
                    if key != "series_by_lab"
                },
                "guideline_rag_agent": {
                    "agent_role": self.rag_agent.role,
                    "retrieved_citations": chief_output["guideline_citations"],
                    "summary": "Retrieved guideline evidence from the curated medical corpus.",
                },
                "chief_synthesis_agent": {
                    "agent_role": chief_output["agent_role"],
                    "overall_risk_level": chief_output["overall_risk_level"],
                    "primary_concern": chief_output["primary_concern"],
                    "chief_summary": chief_output["chief_summary"],
                    "diagnosis_update_blocked": chief_output["diagnosis_update_blocked"],
                    "shift_handoff_summary": chief_output["shift_handoff_summary"],
                },
            },
            "latest_vitals": chief_output["latest_vitals"],
            "current_ml_risk": chief_output["current_ml_risk"],
            "flagged_risks": chief_output["flagged_risks"],
            "probable_lab_errors": chief_output["probable_lab_errors"],
            "disease_progression_timeline": chief_output["disease_progression_timeline"],
            "disease_progression_timeline_by_day": chief_output["disease_progression_timeline_by_day"],
            "guideline_citations": chief_output["guideline_citations"],
            "recommended_actions": chief_output["recommended_actions"],
            "overall_risk_level": chief_output["overall_risk_level"],
            "primary_concern": chief_output["primary_concern"],
            "diagnostic_risk_report": chief_output["diagnostic_risk_report"],
            "explainability": chief_output["explainability"],
            "shift_handoff_summary": chief_output["shift_handoff_summary"],
        }

    def _run_risk_agent(
        self, patient_id: str, latest_features: Dict[str, float], timestamp: str
    ) -> Dict[str, Any] | None:
        if self.risk_agent is None:
            return None
        if not all(name in latest_features for name in FEATURE_NAMES):
            return None

        payload = {
            "patient_id": patient_id,
            "timestamp": timestamp,
            "features": {name: latest_features[name] for name in FEATURE_NAMES},
        }
        try:
            return self.risk_agent.run(payload, record_alert=False)
        except TypeError:
            return self.risk_agent.run(payload)

    @staticmethod
    def _normalize_notes(raw_notes: Any) -> List[Dict[str, Any]]:
        if not isinstance(raw_notes, list):
            return []

        notes: List[Dict[str, Any]] = []
        for index, raw_note in enumerate(raw_notes):
            if isinstance(raw_note, str):
                note = {"text": raw_note, "timestamp": _utc_now(), "author": f"Note {index + 1}"}
            elif isinstance(raw_note, dict):
                note = dict(raw_note)
            else:
                continue

            note.setdefault("timestamp", _utc_now())
            note["sort_key"] = _sort_key(note.get("timestamp"), index)
            notes.append(note)

        notes.sort(key=lambda item: item["sort_key"])
        return notes

    @staticmethod
    def _normalize_labs(raw_labs: Any) -> List[Dict[str, Any]]:
        if not isinstance(raw_labs, list):
            return []

        labs: List[Dict[str, Any]] = []
        for index, raw_lab in enumerate(raw_labs):
            if not isinstance(raw_lab, dict):
                continue
            if "value" not in raw_lab:
                continue
            lab = dict(raw_lab)
            lab.setdefault("timestamp", _utc_now())
            lab["sort_key"] = _sort_key(lab.get("timestamp"), index)
            labs.append(lab)

        labs.sort(key=lambda item: item["sort_key"])
        return labs

    @staticmethod
    def _normalize_vitals(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
        raw_vitals = payload.get("vitals")
        snapshots: List[Dict[str, Any]] = []

        if isinstance(raw_vitals, list):
            source_items = raw_vitals
        elif isinstance(payload.get("features"), dict):
            source_items = [
                {
                    "timestamp": payload.get("timestamp") or _utc_now(),
                    "features": payload.get("features"),
                }
            ]
        else:
            source_items = []

        for index, item in enumerate(source_items):
            if not isinstance(item, dict):
                continue
            raw_features = item.get("features", item)
            if not isinstance(raw_features, dict):
                continue

            features = {}
            for key in MONITORED_VITAL_KEYS:
                if key in raw_features:
                    features[key] = float(raw_features[key])

            if not features:
                continue

            timestamp = str(item.get("timestamp") or item.get("time") or payload.get("timestamp") or _utc_now())
            snapshots.append(
                {
                    "timestamp": timestamp,
                    "sort_key": _sort_key(timestamp, index),
                    "features": features,
                }
            )

        snapshots.sort(key=lambda item: item["sort_key"])
        return snapshots
