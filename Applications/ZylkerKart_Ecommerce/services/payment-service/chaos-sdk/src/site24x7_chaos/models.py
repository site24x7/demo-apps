"""Fault rule configuration model — mirrors the JSON config file structure."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


@dataclass(frozen=True)
class FaultRuleConfig:
    """A single fault injection rule, deserialized from the agent config file."""

    id: str
    fault_type: str
    enabled: bool = True
    probability: float = 1.0
    config: Dict[str, Any] = field(default_factory=dict)
    url_pattern: str = ""

    # --- config helpers ---

    def get_config_str(self, key: str, default: str = "") -> str:
        val = self.config.get(key)
        return str(val) if val is not None else default

    def get_config_int(self, key: str, default: int = 0) -> int:
        val = self.config.get(key)
        if isinstance(val, (int, float)):
            return int(val)
        if isinstance(val, str):
            try:
                return int(val)
            except ValueError:
                return default
        return default

    def get_config_float(self, key: str, default: float = 0.0) -> float:
        val = self.config.get(key)
        if isinstance(val, (int, float)):
            return float(val)
        if isinstance(val, str):
            try:
                return float(val)
            except ValueError:
                return default
        return default


@dataclass
class AppFaultConfig:
    """Top-level config file structure for one application."""

    version: int = 1
    app_name: str = ""
    environment_id: str = ""
    updated_at: str = ""
    rules: List[FaultRuleConfig] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> AppFaultConfig:
        rules = []
        for r in data.get("rules", []):
            rules.append(FaultRuleConfig(
                id=r.get("id", ""),
                fault_type=r.get("fault_type", ""),
                enabled=r.get("enabled", True),
                probability=r.get("probability", 1.0),
                config=r.get("config", {}),
                url_pattern=r.get("url_pattern", ""),
            ))
        return cls(
            version=data.get("version", 1),
            app_name=data.get("app_name", ""),
            environment_id=data.get("environment_id", ""),
            updated_at=data.get("updated_at", ""),
            rules=rules,
        )


# --- Exception class mapping (Java -> Python) ---

# Maps Java exception class names from the config to Python exception classes.
# This allows the same fault rules to work for both Java and Python SDKs.
EXCEPTION_CLASS_MAP: Dict[str, type] = {
    # General Java exceptions
    "java.lang.RuntimeException": RuntimeError,
    "java.lang.IllegalStateException": RuntimeError,
    "java.lang.IllegalArgumentException": ValueError,
    "java.lang.NullPointerException": AttributeError,
    "java.lang.UnsupportedOperationException": NotImplementedError,
    "java.io.IOException": IOError,
    "java.util.concurrent.TimeoutException": TimeoutError,
    # SQL exceptions
    "java.sql.SQLException": Exception,  # Replaced at runtime if SQLAlchemy available
    "java.sql.SQLTransientConnectionException": Exception,
    "java.sql.SQLTimeoutException": TimeoutError,
    "java.sql.SQLNonTransientException": Exception,
    # HTTP client exceptions (Spring)
    "org.springframework.web.client.ResourceAccessException": ConnectionError,
    "org.springframework.web.client.HttpServerErrorException": ConnectionError,
    "org.springframework.web.client.HttpClientErrorException": ConnectionError,
    "java.net.ConnectException": ConnectionError,
    "java.net.SocketTimeoutException": TimeoutError,
    # Redis exceptions
    "org.springframework.data.redis.RedisConnectionFailureException": ConnectionError,
    "org.springframework.data.redis.RedisSystemException": ConnectionError,
    "io.lettuce.core.RedisCommandTimeoutException": TimeoutError,
    "redis.clients.jedis.exceptions.JedisConnectionException": ConnectionError,
}


def resolve_exception_class(java_class_name: str, default: type = RuntimeError) -> type:
    """Resolve a Java exception class name to a Python exception class."""
    return EXCEPTION_CLASS_MAP.get(java_class_name, default)


def _patch_sqlalchemy_exceptions() -> None:
    """Replace placeholder SQL exception mappings with actual SQLAlchemy types."""
    try:
        from sqlalchemy.exc import OperationalError, TimeoutError as SATimeout
        EXCEPTION_CLASS_MAP["java.sql.SQLException"] = OperationalError
        EXCEPTION_CLASS_MAP["java.sql.SQLTransientConnectionException"] = OperationalError
        EXCEPTION_CLASS_MAP["java.sql.SQLTimeoutException"] = SATimeout
        EXCEPTION_CLASS_MAP["java.sql.SQLNonTransientException"] = OperationalError
    except ImportError:
        pass


def _patch_requests_exceptions() -> None:
    """Replace placeholder HTTP client exception mappings with requests types."""
    try:
        import requests.exceptions as re
        EXCEPTION_CLASS_MAP["org.springframework.web.client.ResourceAccessException"] = re.ConnectionError
        EXCEPTION_CLASS_MAP["java.net.ConnectException"] = re.ConnectionError
        EXCEPTION_CLASS_MAP["java.net.SocketTimeoutException"] = re.ReadTimeout
        EXCEPTION_CLASS_MAP["org.springframework.web.client.HttpServerErrorException"] = re.HTTPError
        EXCEPTION_CLASS_MAP["org.springframework.web.client.HttpClientErrorException"] = re.HTTPError
    except ImportError:
        pass


def _patch_redis_exceptions() -> None:
    """Replace placeholder Redis exception mappings with redis-py types."""
    try:
        import redis.exceptions as re
        EXCEPTION_CLASS_MAP["org.springframework.data.redis.RedisConnectionFailureException"] = re.ConnectionError
        EXCEPTION_CLASS_MAP["org.springframework.data.redis.RedisSystemException"] = re.ConnectionError
        EXCEPTION_CLASS_MAP["io.lettuce.core.RedisCommandTimeoutException"] = re.TimeoutError
        EXCEPTION_CLASS_MAP["redis.clients.jedis.exceptions.JedisConnectionException"] = re.ConnectionError
    except ImportError:
        pass
