"""SQLAlchemy database fault injector — 3 fault types.

Fault types handled
-------------------
1. ``jdbc_exception``          — Raise a mapped ``OperationalError`` before the query.
2. ``jdbc_latency``            — Sleep before the query executes.
3. ``jdbc_connection_pool_drain`` — Hold open connections from the pool in
   background threads so legitimate queries timeout.

Integration approach
--------------------
We hook into SQLAlchemy's event system:

* ``before_cursor_execute`` — fired before every SQL statement.  We use it
  for ``jdbc_exception`` and ``jdbc_latency``.
* Connection pool drain runs as a daemon thread that grabs raw connections
  from the engine's pool and holds them for a configurable duration.
"""

from __future__ import annotations

import logging
import threading
import time
from typing import TYPE_CHECKING, Any, Optional

from ..models import FaultRuleConfig, resolve_exception_class

if TYPE_CHECKING:
    from sqlalchemy.engine import Engine

    from ..engine import ChaosEngine

logger = logging.getLogger("site24x7_chaos.fault.database")

_FAULT_PREFIX = "jdbc_"

# Guard against re-registering
_registered_engines: set = set()


class DatabaseFaultInjector:
    """Registers SQLAlchemy event listeners to inject database faults.

    Call :meth:`install` once per :class:`~sqlalchemy.engine.Engine`.
    """

    def __init__(self, engine_ref: ChaosEngine) -> None:
        self._chaos_engine = engine_ref
        self._drain_active = threading.Event()

    def install(self, sa_engine: Engine) -> None:
        """Register event listeners on the SQLAlchemy *sa_engine*."""
        engine_id = id(sa_engine)
        if engine_id in _registered_engines:
            logger.debug("SQLAlchemy engine already registered, skipping")
            return

        from sqlalchemy import event

        @event.listens_for(sa_engine, "before_cursor_execute")
        def _before_cursor_execute(
            conn: Any,
            cursor: Any,
            statement: str,
            parameters: Any,
            context: Any,
            executemany: bool,
        ) -> None:
            self._apply_fault(sa_engine)

        _registered_engines.add(engine_id)
        logger.info("DatabaseFaultInjector installed on SQLAlchemy engine")

    # ------------------------------------------------------------------
    # Evaluation
    # ------------------------------------------------------------------

    def _apply_fault(self, sa_engine: Engine) -> None:
        if not self._chaos_engine.enabled:
            return

        rules = self._chaos_engine.find_matching_rules(_FAULT_PREFIX)

        for rule in rules:
            if not self._chaos_engine.should_fire(rule):
                continue

            fault_type = rule.fault_type
            if fault_type == "jdbc_exception":
                self._apply_exception(rule)
            elif fault_type == "jdbc_latency":
                self._apply_latency(rule)
            elif fault_type == "jdbc_connection_pool_drain":
                self._apply_connection_pool_drain(rule, sa_engine)
            else:
                logger.warning("Unknown JDBC fault type: %s", fault_type)

    # ------------------------------------------------------------------
    # Fault implementations
    # ------------------------------------------------------------------

    @staticmethod
    def _apply_exception(rule: FaultRuleConfig) -> None:
        java_class = rule.get_config_str("exception_class", "java.sql.SQLException")
        message = rule.get_config_str("message", "Injected JDBC fault")
        sql_state = rule.get_config_str("sql_state", "08001")

        logger.debug(
            "Injecting JDBC exception: %s (state: %s)", message, sql_state
        )

        exc_class = resolve_exception_class(java_class)

        # Try to construct with the message.  SQLAlchemy's OperationalError
        # needs special handling (orig, params).
        try:
            from sqlalchemy.exc import OperationalError as SAOpError

            if exc_class is SAOpError or (
                isinstance(exc_class, type) and issubclass(exc_class, SAOpError)
            ):
                # OperationalError(statement, params, orig, ...)
                raise SAOpError(
                    message,
                    params=None,
                    orig=Exception(f"[{sql_state}] {message}"),
                )
        except ImportError:
            pass

        try:
            raise exc_class(message)  # type: ignore[arg-type]
        except TypeError:
            raise RuntimeError(message)

    @staticmethod
    def _apply_latency(rule: FaultRuleConfig) -> None:
        delay_ms = rule.get_config_int("delay_ms", 2000)

        logger.debug("Injecting JDBC latency: %dms", delay_ms)
        time.sleep(delay_ms / 1000.0)

    def _apply_connection_pool_drain(
        self, rule: FaultRuleConfig, sa_engine: Engine
    ) -> None:
        """Hold open connections from the SQLAlchemy pool in a background thread."""
        if self._drain_active.is_set():
            logger.debug("Connection pool drain already active, skipping")
            return

        hold_count = min(max(rule.get_config_int("hold_count", 5), 1), 20)
        hold_duration_ms = min(
            max(rule.get_config_int("hold_duration_ms", 30000), 1000), 60000
        )

        self._drain_active.set()

        logger.info(
            "Injecting connection pool drain: %d connections held for %dms",
            hold_count,
            hold_duration_ms,
        )

        def drain_worker() -> None:
            held: list = []
            try:
                pool = sa_engine.pool
                for i in range(hold_count):
                    try:
                        conn = pool.connect()
                        held.append(conn)
                        logger.debug(
                            "Connection pool drain: acquired %d/%d",
                            i + 1,
                            hold_count,
                        )
                    except Exception as exc:
                        logger.debug(
                            "Connection pool drain: failed to acquire %d/%d: %s",
                            i + 1,
                            hold_count,
                            exc,
                        )
                        break

                logger.info(
                    "Connection pool drain: holding %d connections for %dms",
                    len(held),
                    hold_duration_ms,
                )
                time.sleep(hold_duration_ms / 1000.0)
            finally:
                for conn in held:
                    try:
                        conn.close()
                    except Exception:
                        pass
                self._drain_active.clear()
                logger.info(
                    "Connection pool drain: released %d connections", len(held)
                )

        t = threading.Thread(
            target=drain_worker, name="chaos-db-pool-drain", daemon=True
        )
        t.start()
