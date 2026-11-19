"""Configuration settings for ZylkerBank API Gateway."""

import os
from functools import lru_cache
from pydantic import BaseModel


class Settings(BaseModel):
    service_name: str = "api-gateway"
    port: int = int(os.environ.get("PORT", "8000"))
    portal_url: str = os.environ.get("PORTAL_URL", "http://banking-portal:8080").rstrip("/")
    ledger_url: str = os.environ.get("LEDGER_URL", "http://ledger-service:8081").rstrip("/")
    gateway_url: str = os.environ.get("GATEWAY_URL", "http://financial-gateway:8082").rstrip("/")
    ai_url: str = os.environ.get("AI_URL", "http://ai-risk-service:8083").rstrip("/")

    # Site24x7 Chaos SDK
    chaos_enabled: bool = os.environ.get("CHAOS_SDK_ENABLED", "true").lower() in ("true", "1", "yes")
    chaos_app_name: str = os.environ.get("CHAOS_SDK_APP_NAME", "api-gateway")
    chaos_config_dir: str = os.environ.get("CHAOS_SDK_CONFIG_DIR", "/var/site24x7-labs/faults")


@lru_cache()
def get_settings() -> Settings:
    return Settings()
