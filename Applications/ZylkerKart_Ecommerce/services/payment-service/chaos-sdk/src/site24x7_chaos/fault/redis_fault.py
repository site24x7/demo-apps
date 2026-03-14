"""Redis fault injector — monkey-patches ``redis.Redis.execute_command``.

Fault types handled
-------------------
1. ``redis_exception`` — Raise a mapped ``redis.exceptions.ConnectionError``
   (or similar) before the Redis command executes.
2. ``redis_latency``   — Sleep before the Redis command executes.

Monkey-patching approach
------------------------
We wrap ``redis.Redis.execute_command`` which is the single point through
which *all* Redis commands flow (GET, SET, HGETALL, etc.).  This is the
Python equivalent of wrapping the ``RedisConnectionFactory`` in Spring.
"""

from __future__ import annotations

import logging
import time
from typing import TYPE_CHECKING, Any

from ..models import FaultRuleConfig, resolve_exception_class

if TYPE_CHECKING:
    from ..engine import ChaosEngine

logger = logging.getLogger("site24x7_chaos.fault.redis_fault")

_FAULT_PREFIX = "redis_"

# Sentinel to track whether we've already patched
_patched = False


class RedisFaultInjector:
    """Evaluates ``redis_*`` fault rules and monkey-patches ``redis-py``.

    Call :meth:`install` once after the engine is started.
    """

    def __init__(self, engine: ChaosEngine) -> None:
        self._engine = engine

    def install(self) -> None:
        """Monkey-patch ``redis.Redis.execute_command``."""
        global _patched
        if _patched:
            return

        try:
            import redis as redis_lib  # noqa: F811
        except ImportError:
            logger.debug("redis-py not installed, skipping Redis fault patching")
            return

        original_execute = redis_lib.Redis.execute_command
        engine = self._engine

        def patched_execute_command(
            redis_self: Any, *args: Any, **kwargs: Any
        ) -> Any:
            _evaluate(engine)
            return original_execute(redis_self, *args, **kwargs)

        redis_lib.Redis.execute_command = patched_execute_command  # type: ignore[assignment]
        _patched = True
        logger.info("Monkey-patched redis.Redis.execute_command")


# ------------------------------------------------------------------
# Shared evaluation logic
# ------------------------------------------------------------------


def _evaluate(engine: ChaosEngine) -> None:
    """Evaluate ``redis_*`` rules and apply faults inline (raise or sleep)."""
    if not engine.enabled:
        return

    rules = engine.find_matching_rules(_FAULT_PREFIX)

    for rule in rules:
        if not engine.should_fire(rule):
            continue

        fault_type = rule.fault_type
        if fault_type == "redis_exception":
            _apply_exception(rule)
        elif fault_type == "redis_latency":
            _apply_latency(rule)
        else:
            logger.warning("Unknown Redis fault type: %s", fault_type)


def _apply_exception(rule: FaultRuleConfig) -> None:
    java_class = rule.get_config_str(
        "exception_class",
        "org.springframework.data.redis.RedisConnectionFailureException",
    )
    message = rule.get_config_str("message", "Injected Redis fault")

    logger.debug("Injecting Redis exception: %s - %s", java_class, message)

    exc_class = resolve_exception_class(java_class, default=ConnectionError)

    try:
        raise exc_class(message)  # type: ignore[arg-type]
    except TypeError:
        raise ConnectionError(message)


def _apply_latency(rule: FaultRuleConfig) -> None:
    delay_ms = rule.get_config_int("delay_ms", 2000)

    logger.debug("Injecting Redis latency: %dms", delay_ms)
    time.sleep(delay_ms / 1000.0)
