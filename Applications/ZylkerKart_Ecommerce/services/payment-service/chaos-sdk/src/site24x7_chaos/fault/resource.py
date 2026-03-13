"""Resource / JVM-equivalent fault injector — 6 fault types.

All faults run in daemon threads with a bounded duration so they
self-clean and cannot outlive the process.

Fault types handled
-------------------
1. ``thread_pool_exhaustion`` — Spawn busy-sleeping threads.
2. ``memory_pressure``        — Allocate large bytearrays on the heap.
3. ``cpu_burn``               — Tight math loops across multiple threads.
4. ``gc_pressure``            — Rapid short-lived allocations to stress the GC.
5. ``thread_deadlock``        — Two threads that deadlock on ``threading.Lock``.
6. ``disk_fill``              — Write temp files to consume disk space.

Trigger model
-------------
Unlike HTTP/JDBC/Redis faults, resource faults are **not** triggered per-request.
Instead, the :class:`ResourceFaultInjector` registers as a config-update listener
on the :class:`ChaosEngine`.  When the agent pushes a new config, the injector
checks for active resource rules and fires the first one (only one resource fault
can be active at a time to prevent cascading issues).
"""

from __future__ import annotations

import gc
import logging
import math
import os
import random
import tempfile
import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING, List

from ..models import FaultRuleConfig

if TYPE_CHECKING:
    from ..engine import ChaosEngine

logger = logging.getLogger("site24x7_chaos.fault.resource")

_RESOURCE_FAULT_TYPES = frozenset(
    {
        "thread_pool_exhaustion",
        "memory_pressure",
        "cpu_burn",
        "gc_pressure",
        "thread_deadlock",
        "disk_fill",
    }
)


class ResourceFaultInjector:
    """Registers as a config-update listener and fires resource faults.

    Usage::

        injector = ResourceFaultInjector(engine)
        injector.install()   # registers the listener
    """

    def __init__(self, engine: ChaosEngine) -> None:
        self._engine = engine
        self._active = threading.Event()

    def install(self) -> None:
        """Register as a config-update listener on the engine."""
        self._engine.add_config_update_listener(self._on_config_update)
        logger.info("ResourceFaultInjector installed")

    # ------------------------------------------------------------------
    # Listener
    # ------------------------------------------------------------------

    def _on_config_update(self) -> None:
        self.evaluate_and_apply()

    def evaluate_and_apply(self) -> None:
        """Check active rules for resource faults and fire the first match."""
        if not self._engine.enabled:
            return

        if self._active.is_set():
            logger.debug("Resource fault already active, skipping")
            return

        rules: List[FaultRuleConfig] = [
            r
            for r in self._engine.active_rules
            if r.fault_type in _RESOURCE_FAULT_TYPES and self._engine.should_fire(r)
        ]

        if not rules:
            return

        rule = rules[0]
        ft = rule.fault_type
        if ft == "thread_pool_exhaustion":
            self._apply_thread_pool_exhaustion(rule)
        elif ft == "memory_pressure":
            self._apply_memory_pressure(rule)
        elif ft == "cpu_burn":
            self._apply_cpu_burn(rule)
        elif ft == "gc_pressure":
            self._apply_gc_pressure(rule)
        elif ft == "thread_deadlock":
            self._apply_thread_deadlock(rule)
        elif ft == "disk_fill":
            self._apply_disk_fill(rule)
        else:
            logger.warning("Unknown resource fault type: %s", ft)

    # ------------------------------------------------------------------
    # 1. Thread pool exhaustion
    # ------------------------------------------------------------------

    def _apply_thread_pool_exhaustion(self, rule: FaultRuleConfig) -> None:
        thread_count = _clamp(rule.get_config_int("thread_count", 10), 1, 50)
        duration_ms = _clamp(rule.get_config_int("duration_ms", 30000), 1000, 60000)

        logger.info(
            "Injecting thread pool exhaustion: %d threads for %dms",
            thread_count,
            duration_ms,
        )
        self._active.set()

        def orchestrator() -> None:
            barrier = threading.Barrier(thread_count + 1, timeout=duration_ms / 1000.0 + 5)
            workers: list[threading.Thread] = []

            def worker() -> None:
                try:
                    time.sleep(duration_ms / 1000.0)
                finally:
                    try:
                        barrier.wait()
                    except threading.BrokenBarrierError:
                        pass

            try:
                for i in range(thread_count):
                    t = threading.Thread(
                        target=worker,
                        name=f"chaos-thread-exhaust-{i}",
                        daemon=True,
                    )
                    workers.append(t)
                    t.start()
                try:
                    barrier.wait()
                except threading.BrokenBarrierError:
                    pass
                logger.info("Thread pool exhaustion fault completed")
            finally:
                self._active.clear()

        threading.Thread(
            target=orchestrator,
            name="chaos-thread-exhaust-orchestrator",
            daemon=True,
        ).start()

    # ------------------------------------------------------------------
    # 2. Memory pressure
    # ------------------------------------------------------------------

    def _apply_memory_pressure(self, rule: FaultRuleConfig) -> None:
        allocation_mb = _clamp(rule.get_config_int("allocation_mb", 64), 1, 512)
        duration_ms = _clamp(rule.get_config_int("duration_ms", 30000), 1000, 60000)

        logger.info(
            "Injecting memory pressure: %dMB for %dms",
            allocation_mb,
            duration_ms,
        )
        self._active.set()

        def mem_worker() -> None:
            blocks: list[bytearray] | None = None
            try:
                blocks = []
                for i in range(allocation_mb):
                    block = bytearray(1024 * 1024)  # 1 MB
                    # Touch the memory at page boundaries to ensure real allocation
                    for offset in range(0, len(block), 4096):
                        block[offset] = i & 0xFF
                    blocks.append(block)
                logger.debug("Memory pressure: allocated %dMB", allocation_mb)
                time.sleep(duration_ms / 1000.0)
            except MemoryError:
                logger.warning(
                    "Memory pressure: MemoryError during allocation, holding partial"
                )
                time.sleep(duration_ms / 1000.0)
            finally:
                del blocks
                gc.collect()
                self._active.clear()
                logger.info("Memory pressure fault completed, memory released")

        threading.Thread(
            target=mem_worker, name="chaos-memory-pressure", daemon=True
        ).start()

    # ------------------------------------------------------------------
    # 3. CPU burn
    # ------------------------------------------------------------------

    def _apply_cpu_burn(self, rule: FaultRuleConfig) -> None:
        thread_count = _clamp(rule.get_config_int("thread_count", 2), 1, 8)
        duration_ms = _clamp(rule.get_config_int("duration_ms", 30000), 1000, 60000)

        logger.info(
            "Injecting CPU burn: %d threads for %dms", thread_count, duration_ms
        )
        self._active.set()

        end_time = time.monotonic() + duration_ms / 1000.0
        barrier = threading.Barrier(thread_count + 1, timeout=duration_ms / 1000.0 + 5)

        def burner() -> None:
            try:
                x = random.random()
                while time.monotonic() < end_time:
                    for _ in range(1000):
                        x = math.sin(x) * math.cos(x)
            finally:
                try:
                    barrier.wait()
                except threading.BrokenBarrierError:
                    pass

        def orchestrator() -> None:
            try:
                for i in range(thread_count):
                    threading.Thread(
                        target=burner,
                        name=f"chaos-cpu-burn-{i}",
                        daemon=True,
                    ).start()
                try:
                    barrier.wait()
                except threading.BrokenBarrierError:
                    pass
                logger.info("CPU burn fault completed")
            finally:
                self._active.clear()

        threading.Thread(
            target=orchestrator,
            name="chaos-cpu-burn-orchestrator",
            daemon=True,
        ).start()

    # ------------------------------------------------------------------
    # 4. GC pressure
    # ------------------------------------------------------------------

    def _apply_gc_pressure(self, rule: FaultRuleConfig) -> None:
        alloc_rate = _clamp(
            rule.get_config_int("allocation_rate_mb_per_sec", 10), 1, 100
        )
        duration_ms = _clamp(rule.get_config_int("duration_ms", 30000), 1000, 60000)

        logger.info(
            "Injecting GC pressure: %dMB/sec for %dms", alloc_rate, duration_ms
        )
        self._active.set()

        def gc_worker() -> None:
            try:
                end_time = time.monotonic() + duration_ms / 1000.0
                sleep_s = max(0.001, 1.0 / alloc_rate)
                while time.monotonic() < end_time:
                    # Allocate 1MB — short-lived so the GC must collect it
                    garbage = bytearray(1024 * 1024)
                    garbage[0] = 1
                    garbage[-1] = 1
                    del garbage
                    time.sleep(sleep_s)
                logger.info("GC pressure fault completed")
            except MemoryError:
                logger.warning("GC pressure: MemoryError, stopping early")
            finally:
                self._active.clear()

        threading.Thread(
            target=gc_worker, name="chaos-gc-pressure", daemon=True
        ).start()

    # ------------------------------------------------------------------
    # 5. Thread deadlock
    # ------------------------------------------------------------------

    def _apply_thread_deadlock(self, rule: FaultRuleConfig) -> None:
        duration_ms = _clamp(rule.get_config_int("duration_ms", 30000), 1000, 60000)

        logger.info("Injecting thread deadlock for %dms", duration_ms)
        self._active.set()

        lock_a = threading.Lock()
        lock_b = threading.Lock()
        stop_event = threading.Event()

        def thread_1() -> None:
            lock_a.acquire()
            try:
                time.sleep(0.05)
                # This will block forever (deadlock) until stop_event
                while not stop_event.is_set():
                    if lock_b.acquire(timeout=0.1):
                        try:
                            time.sleep(duration_ms / 1000.0)
                        finally:
                            lock_b.release()
                        break
            finally:
                lock_a.release()

        def thread_2() -> None:
            lock_b.acquire()
            try:
                time.sleep(0.05)
                while not stop_event.is_set():
                    if lock_a.acquire(timeout=0.1):
                        try:
                            time.sleep(duration_ms / 1000.0)
                        finally:
                            lock_a.release()
                        break
            finally:
                lock_b.release()

        def watchdog() -> None:
            try:
                t1 = threading.Thread(
                    target=thread_1, name="chaos-deadlock-1", daemon=True
                )
                t2 = threading.Thread(
                    target=thread_2, name="chaos-deadlock-2", daemon=True
                )
                t1.start()
                t2.start()
                time.sleep(duration_ms / 1000.0)
            finally:
                stop_event.set()
                self._active.clear()
                logger.info("Thread deadlock fault completed")

        threading.Thread(
            target=watchdog, name="chaos-deadlock-watchdog", daemon=True
        ).start()

    # ------------------------------------------------------------------
    # 6. Disk fill
    # ------------------------------------------------------------------

    def _apply_disk_fill(self, rule: FaultRuleConfig) -> None:
        allocation_mb = _clamp(rule.get_config_int("allocation_mb", 64), 1, 512)
        duration_ms = _clamp(rule.get_config_int("duration_ms", 30000), 1000, 60000)

        logger.info(
            "Injecting disk fill: %dMB for %dms", allocation_mb, duration_ms
        )
        self._active.set()

        def disk_worker() -> None:
            temp_files: list[Path] = []
            try:
                tmp_dir = Path(tempfile.gettempdir())
                block = b"\xAA" * (1024 * 1024)  # 1 MB

                for i in range(allocation_mb):
                    fp = tmp_dir / f"chaos-disk-fill-{i}.tmp"
                    fp.write_bytes(block)
                    temp_files.append(fp)

                logger.debug("Disk fill: wrote %dMB of temp files", allocation_mb)
                time.sleep(duration_ms / 1000.0)
            except OSError as exc:
                logger.warning("Disk fill: error during writing: %s", exc)
            finally:
                for fp in temp_files:
                    try:
                        fp.unlink(missing_ok=True)
                    except OSError:
                        pass
                self._active.clear()
                logger.info(
                    "Disk fill fault completed, %d temp files cleaned up",
                    len(temp_files),
                )

        threading.Thread(
            target=disk_worker, name="chaos-disk-fill", daemon=True
        ).start()


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------


def _clamp(value: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, value))
