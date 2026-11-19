"""Environment-driven configuration (localhost defaults, docker overrides via env)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache


def _bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None or not raw.strip():
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, "").strip() or default)
    except ValueError:
        return default


def _float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, "").strip() or default)
    except ValueError:
        return default


def _str(name: str, default: str) -> str:
    val = os.environ.get(name)
    return val.strip() if val is not None and val.strip() else default


@dataclass(frozen=True)
class Settings:
    service_name: str = "ai-risk-service"
    port: int = 8083

    # PostgreSQL
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "bank_db"
    db_user: str = "postgres"
    db_password: str = "ZylkerBank@2024"
    db_pool_min: int = 1
    db_pool_max: int = 10
    db_connect_timeout: float = 3.0

    # Kafka
    kafka_enabled: bool = True
    kafka_brokers: str = "localhost:9092"
    kafka_group_id: str = "bank-audit-consumers"
    kafka_topics: tuple[str, ...] = ("bank.transfers.v1", "bank.cards.v1")

    # Peer services
    ledger_url: str = "http://localhost:8081"
    gateway_url: str = "http://localhost:8082"
    http_timeout: float = 5.0

    # Auth
    jwt_secret: str = "zylkerbank-dev-jwt-secret-please-change-0123456789"
    internal_token: str = "zylkerbank-internal-dev-token"
    require_internal_token: bool = False  # contract: "tolerate missing in dev"
    audit_auth_required: bool = False

    # LLM
    llm_model: str = "ollama/llama3"
    llm_api_base: str = "http://localhost:11434"
    llm_api_key: str = ""
    llm_fallback_enabled: bool = True
    llm_timeout: float = 60.0
    llm_temperature: float = 0.2
    llm_max_iterations: int = 5
    chat_history_limit: int = 20

    # Risk engine
    risk_timezone: str = "UTC"

    # Observability
    traceloop_enabled: bool = False
    otlp_endpoint: str = "http://otel-collector:4318"
    log_level: str = "INFO"
    log_format: str = "json"  # json | text

    # Chaos SDK
    chaos_enabled: bool = True
    chaos_app_name: str = "ai-risk-service"
    chaos_config_dir: str = "/var/site24x7-labs/faults"

    cors_origins: tuple[str, ...] = field(default_factory=lambda: ("*",))

    @property
    def db_dsn(self) -> str:
        from urllib.parse import quote

        return (
            f"postgresql://{quote(self.db_user, safe='')}:{quote(self.db_password, safe='')}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )


def load_settings() -> Settings:
    topics = tuple(
        t.strip()
        for t in _str("KAFKA_TOPICS", "bank.transfers.v1,bank.cards.v1").split(",")
        if t.strip()
    )
    return Settings(
        port=_int("PORT", 8083),
        db_host=_str("DB_HOST", "localhost"),
        db_port=_int("DB_PORT", 5432),
        db_name=_str("DB_NAME", "bank_db"),
        db_user=_str("DB_USER", "postgres"),
        db_password=_str("DB_PASSWORD", "ZylkerBank@2024"),
        db_pool_min=_int("DB_POOL_MIN", 1),
        db_pool_max=_int("DB_POOL_MAX", 10),
        db_connect_timeout=_float("DB_CONNECT_TIMEOUT", 3.0),
        kafka_enabled=_bool("KAFKA_ENABLED", True),
        kafka_brokers=_str("KAFKA_BROKERS", "localhost:9092"),
        kafka_group_id=_str("KAFKA_GROUP_ID", "bank-audit-consumers"),
        kafka_topics=topics,
        ledger_url=_str("LEDGER_URL", "http://localhost:8081").rstrip("/"),
        gateway_url=_str("GATEWAY_URL", "http://localhost:8082").rstrip("/"),
        http_timeout=_float("HTTP_TIMEOUT_SECONDS", 5.0),
        jwt_secret=_str("JWT_SECRET", "zylkerbank-dev-jwt-secret-please-change-0123456789"),
        internal_token=_str("INTERNAL_TOKEN", "zylkerbank-internal-dev-token"),
        require_internal_token=_bool("REQUIRE_INTERNAL_TOKEN", False),
        audit_auth_required=_bool("AUDIT_AUTH_REQUIRED", False),
        llm_model=_str("LLM_MODEL", "ollama/llama3"),
        llm_api_base=_str("LLM_API_BASE", "http://localhost:11434"),
        llm_api_key=os.environ.get("LLM_API_KEY", "").strip(),
        llm_fallback_enabled=_bool("LLM_FALLBACK_ENABLED", True),
        llm_timeout=_float("LLM_TIMEOUT_SECONDS", 60.0),
        llm_temperature=_float("LLM_TEMPERATURE", 0.2),
        llm_max_iterations=max(1, _int("LLM_MAX_ITERATIONS", 5)),
        chat_history_limit=max(0, _int("CHAT_HISTORY_LIMIT", 20)),
        risk_timezone=_str("RISK_TIMEZONE", "UTC"),
        traceloop_enabled=_bool("TRACELOOP_ENABLED", False),
        otlp_endpoint=_str("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4318").rstrip("/"),
        log_level=_str("LOG_LEVEL", "INFO").upper(),
        log_format=_str("LOG_FORMAT", "json").lower(),
        chaos_enabled=_bool("CHAOS_SDK_ENABLED", True),
        chaos_app_name=_str("CHAOS_SDK_APP_NAME", "ai-risk-service"),
        chaos_config_dir=_str("CHAOS_SDK_CONFIG_DIR", "/var/site24x7-labs/faults"),
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return load_settings()
