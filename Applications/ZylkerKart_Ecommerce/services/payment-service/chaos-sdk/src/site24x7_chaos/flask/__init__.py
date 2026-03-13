"""Flask integration — one-liner setup.

Usage::

    from flask import Flask
    from site24x7_chaos.flask import init_chaos

    app = Flask(__name__)
    init_chaos(app)                        # all defaults from env vars
    # or
    init_chaos(app, app_name="my-service") # explicit overrides
"""

from __future__ import annotations

import atexit
import logging
from typing import TYPE_CHECKING, Optional

from ..engine import ChaosEngine
from ..fault.http_client import HttpClientFaultInjector
from ..fault.redis_fault import RedisFaultInjector
from ..fault.resource import ResourceFaultInjector
from ..models import (
    _patch_redis_exceptions,
    _patch_requests_exceptions,
    _patch_sqlalchemy_exceptions,
)
from .middleware import ChaosFlaskMiddleware

if TYPE_CHECKING:
    from flask import Flask
    from sqlalchemy.engine import Engine as SAEngine

logger = logging.getLogger("site24x7_chaos.flask")


def _get_flask_version() -> str:
    """Best-effort Flask version detection."""
    try:
        import flask

        return getattr(flask, "__version__", "")
    except Exception:
        return ""


def init_chaos(
    app: Flask,
    *,
    app_name: str = "",
    config_dir: str = "",
    enabled: bool = True,
    poll_interval_s: float = 2.0,
    sqlalchemy_engine: Optional[SAEngine] = None,
) -> ChaosEngine:
    """Initialize the Chaos SDK for a Flask application.

    This single call:

    1. Creates and starts a :class:`ChaosEngine` (config file watcher).
    2. Registers :class:`ChaosFlaskMiddleware` (inbound HTTP faults).
    3. Monkey-patches ``requests`` / ``httpx`` (outbound HTTP faults).
    4. Installs SQLAlchemy event listeners (if *sqlalchemy_engine* provided).
    5. Monkey-patches ``redis-py`` (Redis faults).
    6. Registers :class:`ResourceFaultInjector` (resource faults).

    Parameters
    ----------
    app:
        The Flask application instance.
    app_name:
        Application name (overrides ``CHAOS_SDK_APP_NAME`` env var).
    config_dir:
        Config directory (overrides ``CHAOS_SDK_CONFIG_DIR`` env var).
    enabled:
        Master kill-switch (overrides ``CHAOS_SDK_ENABLED`` env var).
    poll_interval_s:
        Config file poll interval in seconds.
    sqlalchemy_engine:
        Optional SQLAlchemy engine to install DB fault injection on.

    Returns
    -------
    ChaosEngine
        The engine instance (useful for testing or manual control).
    """
    # Patch exception mappings for available libraries
    _patch_sqlalchemy_exceptions()
    _patch_requests_exceptions()
    _patch_redis_exceptions()

    # Create & start engine
    engine = ChaosEngine(
        enabled=enabled,
        app_name=app_name,
        config_dir=config_dir,
        poll_interval_s=poll_interval_s,
        framework="flask",
        framework_version=_get_flask_version(),
    )
    engine.start()

    # Stop engine on process exit
    atexit.register(engine.stop)

    if not engine.enabled:
        logger.info("Chaos SDK disabled, skipping middleware registration")
        return engine

    # 1. Inbound HTTP middleware
    ChaosFlaskMiddleware(app, engine)

    # 2. Outbound HTTP (requests + httpx)
    HttpClientFaultInjector(engine).install()

    # 3. SQLAlchemy
    if sqlalchemy_engine is not None:
        from ..fault.database import DatabaseFaultInjector

        DatabaseFaultInjector(engine).install(sqlalchemy_engine)

    # 4. Redis
    RedisFaultInjector(engine).install()

    # 5. Resource faults
    ResourceFaultInjector(engine).install()

    logger.info("Chaos SDK initialized for Flask app '%s'", engine.app_name)
    return engine
