from __future__ import annotations

import json
import os
from typing import Any, Dict, List, Optional

try:  # pragma: no cover - optional dependency
    import psycopg
    from psycopg.types.json import Jsonb
except Exception:  # pragma: no cover
    psycopg = None
    Jsonb = None


class PostgresCaseStore:
    """Local PostgreSQL persistence for doctor cases."""

    def __init__(self, table_name: str = "doctor_cases", dsn: Optional[str] = None) -> None:
        self.table_name = table_name
        self.dsn = dsn or self._build_dsn()
        self.configured = psycopg is not None and bool(self.dsn)
        self.enabled = self.configured
        self.last_error: Optional[str] = None
        self._schema_ready = False

        if self.configured:
            self._initialize()

    def _build_dsn(self) -> str:
        explicit = os.getenv("ICU_DATABASE_URL") or os.getenv("DATABASE_URL")
        if explicit:
            return explicit

        dbname = os.getenv("POSTGRES_DB")
        user = os.getenv("POSTGRES_USER")
        password = os.getenv("POSTGRES_PASSWORD")
        host = os.getenv("POSTGRES_HOST", "127.0.0.1")
        port = os.getenv("POSTGRES_PORT", "5432")

        if dbname:
            parts = [f"dbname={dbname}"]
            if user:
                parts.append(f"user={user}")
            if password:
                parts.append(f"password={password}")
            if os.getenv("POSTGRES_HOST"):
                parts.append(f"host={host}")
            if os.getenv("POSTGRES_PORT"):
                parts.append(f"port={port}")
            return " ".join(parts)

        # Friendly local default: same-user access to a local `icu_agent` DB.
        local_user = user or os.getenv("USER") or os.getenv("USERNAME")
        if local_user:
            parts = ["dbname=icu_agent", f"user={local_user}"]
            return " ".join(parts)

        return ""

    def _initialize(self) -> None:
        if not self.configured:
            return
        try:
            with self._connect() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        f"""
                        CREATE TABLE IF NOT EXISTS {self.table_name} (
                            patient_id TEXT PRIMARY KEY,
                            case_data JSONB NOT NULL,
                            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                        )
                        """
                    )
                conn.commit()
            self._schema_ready = True
            self.last_error = None
        except Exception as exc:  # pragma: no cover - depends on local db setup
            self.last_error = str(exc)
            self._schema_ready = False

    def _connect(self):
        if not self.configured or psycopg is None:
            raise RuntimeError("PostgreSQL storage is not enabled.")
        return psycopg.connect(self.dsn)

    def _ensure_schema(self) -> bool:
        if not self.configured:
            return False
        if self._schema_ready:
            return True
        self._initialize()
        return self._schema_ready

    def _normalize_case(self, raw_case: Any) -> Optional[Dict[str, Any]]:
        if isinstance(raw_case, dict):
            return json.loads(json.dumps(raw_case))
        if isinstance(raw_case, str):
            try:
                decoded = json.loads(raw_case)
            except json.JSONDecodeError:
                return None
            if isinstance(decoded, dict):
                return decoded
        return None

    def upsert_case(self, case: Dict[str, Any]) -> None:
        if not self._ensure_schema() or Jsonb is None:
            return

        payload = json.loads(json.dumps(case))
        try:
            with self._connect() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        f"""
                        INSERT INTO {self.table_name} (patient_id, case_data, created_at, updated_at)
                        VALUES (%s, %s, COALESCE(%s::timestamptz, NOW()), COALESCE(%s::timestamptz, NOW()))
                        ON CONFLICT (patient_id)
                        DO UPDATE SET
                            case_data = EXCLUDED.case_data,
                            updated_at = EXCLUDED.updated_at
                        """,
                        (
                            case.get("patient_id", ""),
                            Jsonb(payload),
                            case.get("created_at"),
                            case.get("updated_at"),
                        ),
                    )
                conn.commit()
            self.last_error = None
        except Exception as exc:  # pragma: no cover - depends on local db setup
            self.last_error = str(exc)
            self._schema_ready = False

    def fetch_case(self, patient_id: str) -> Optional[Dict[str, Any]]:
        if not self._ensure_schema():
            return None

        try:
            with self._connect() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        f"SELECT case_data FROM {self.table_name} WHERE patient_id = %s",
                        (patient_id,),
                    )
                    row = cur.fetchone()
            self.last_error = None
        except Exception as exc:  # pragma: no cover - depends on local db setup
            self.last_error = str(exc)
            self._schema_ready = False
            return None

        if not row:
            return None
        return self._normalize_case(row[0])

    def list_cases(self) -> List[Dict[str, Any]]:
        if not self._ensure_schema():
            return []

        try:
            with self._connect() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        f"SELECT case_data FROM {self.table_name} ORDER BY updated_at DESC"
                    )
                    rows = cur.fetchall()
            self.last_error = None
        except Exception as exc:  # pragma: no cover - depends on local db setup
            self.last_error = str(exc)
            self._schema_ready = False
            return []

        cases: List[Dict[str, Any]] = []
        for row in rows:
            normalized = self._normalize_case(row[0])
            if normalized is not None:
                cases.append(normalized)
        return cases

    def is_connected(self) -> bool:
        if not self.configured:
            return False
        try:
            with self._connect() as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    cur.fetchone()
            self.last_error = None
            return True
        except Exception as exc:  # pragma: no cover - depends on local db setup
            self.last_error = str(exc)
            self._schema_ready = False
            return False

    def status(self) -> Dict[str, Any]:
        return {
            "backend": "postgresql",
            "configured": self.configured,
            "connected": self.is_connected(),
            "table": self.table_name,
            "dsn": self.dsn,
            "last_error": self.last_error,
        }
