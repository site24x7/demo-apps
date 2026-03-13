"""Central chaos engine that coordinates fault injection.

Thread-safety model
-------------------
* ``_active_rules`` is a plain list that is *replaced atomically* (copy-on-write)
  behind a :class:`threading.Lock`.
* Request-handling threads call :meth:`find_matching_rules` and
  :meth:`should_fire` which only *read* the list reference — no lock needed
  because Python's GIL guarantees reference reads are atomic.
* The :class:`ConfigFileWatcher` thread calls :meth:`_on_config_update` which
  acquires the lock, builds a new list, and swaps the reference.
"""

from __future__ import annotations

import logging
import os
import random
import re as _re
import threading
from typing import Callable, List, Optional

from .config import ConfigFileWatcher, HeartbeatWriter
from .models import AppFaultConfig, FaultRuleConfig

logger = logging.getLogger("site24x7_chaos.engine")

# Default config directory (where the agent writes fault configs)
_DEFAULT_CONFIG_DIR = "/var/site24x7-labs/faults"
_DEFAULT_POLL_INTERVAL_S = 2.0


class ChaosEngine:
    """Singleton-style engine that manages fault rules and the config watcher.

    Parameters
    ----------
    enabled:
        Master kill-switch.  ``False`` disables all fault injection.
    app_name:
        Application name — must match the ``app_name`` in the config file
        written by the agent.
    config_dir:
        Directory where the agent writes ``{app_name}.json``.
    poll_interval_s:
        How often (seconds) the watcher checks for file changes.
    """

    def __init__(
        self,
        enabled: bool = True,
        app_name: str = "",
        config_dir: str = "",
        poll_interval_s: float = _DEFAULT_POLL_INTERVAL_S,
        framework: str = "",
        framework_version: str = "",
    ) -> None:
        # Env var overrides the explicit arg only when the arg is default (True).
        # If caller explicitly passes enabled=False, that wins.
        if not enabled:
            self._enabled = False
        else:
            self._enabled = _env_bool("CHAOS_SDK_ENABLED", True)

        self._app_name = app_name or os.environ.get("CHAOS_SDK_APP_NAME", "")
        self._config_dir = config_dir or os.environ.get("CHAOS_SDK_CONFIG_DIR", _DEFAULT_CONFIG_DIR)
        self._poll_interval_s = poll_interval_s
        self._framework = framework
        self._framework_version = framework_version

        # Thread-safe active rules (copy-on-write)
        self._lock = threading.Lock()
        self._active_rules: List[FaultRuleConfig] = []

        # Config update listeners (e.g., ResourceFaultInjector)
        self._config_listeners: List[Callable[[], None]] = []

        # Watcher (created on start)
        self._watcher: Optional[ConfigFileWatcher] = None

        # Heartbeat writer (created on start)
        self._heartbeat: Optional[HeartbeatWriter] = None

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the config file watcher daemon thread."""
        if not self._enabled:
            logger.info("Chaos SDK is disabled")
            return

        if not self._app_name:
            logger.warning("CHAOS_SDK_APP_NAME not set, fault injection disabled")
            return

        config_file = os.path.join(self._config_dir, f"{self._app_name}.json")
        self._watcher = ConfigFileWatcher(
            config_file=config_file,
            listener=self._on_config_update,
            poll_interval_s=self._poll_interval_s,
        )
        self._watcher.start()
        logger.info(
            "ChaosEngine started for app '%s', config file: %s",
            self._app_name,
            config_file,
        )

        # Start heartbeat writer so the agent can detect SDK presence
        from . import __version__ as sdk_version

        self._heartbeat = HeartbeatWriter(
            config_dir=self._config_dir,
            app_name=self._app_name,
            sdk_version=sdk_version,
            framework=self._framework,
            framework_version=self._framework_version,
        )
        self._heartbeat.start()

    def stop(self) -> None:
        """Stop the config file watcher and heartbeat writer."""
        if self._heartbeat is not None:
            self._heartbeat.stop()
            self._heartbeat = None
        if self._watcher is not None:
            self._watcher.stop()
            self._watcher = None
        logger.info("ChaosEngine stopped")

    # ------------------------------------------------------------------
    # Config update
    # ------------------------------------------------------------------

    def _on_config_update(self, config: AppFaultConfig) -> None:
        """Called by ConfigFileWatcher when the config file changes."""
        enabled_rules = [r for r in config.rules if r.enabled]
        with self._lock:
            self._active_rules = enabled_rules
        logger.debug("Active rules updated: %d rules", len(enabled_rules))

        # Notify listeners (e.g., ResourceFaultInjector triggers on config change)
        for listener in self._config_listeners:
            try:
                listener()
            except Exception:
                logger.error("Config update listener error", exc_info=True)

    def add_config_update_listener(self, listener: Callable[[], None]) -> None:
        """Register a callback invoked whenever active rules are updated.

        Used by resource fault injectors that trigger on config changes
        (not on every request).
        """
        self._config_listeners.append(listener)

    # ------------------------------------------------------------------
    # Rule matching
    # ------------------------------------------------------------------

    def find_matching_rules(
        self,
        fault_type_prefix: str,
        request_url: str = "",
    ) -> List[FaultRuleConfig]:
        """Return all active rules whose ``fault_type`` starts with *prefix*
        and whose ``url_pattern`` matches *request_url*.
        """
        if not self._enabled:
            return []

        rules = self._active_rules  # single atomic read
        if not rules:
            return []

        return [
            r
            for r in rules
            if r.fault_type.startswith(fault_type_prefix)
            and _matches_url(r.url_pattern, request_url)
        ]

    @staticmethod
    def should_fire(rule: FaultRuleConfig) -> bool:
        """Check whether the fault should actually fire based on probability."""
        if rule.probability >= 1.0:
            return True
        if rule.probability <= 0.0:
            return False
        return random.random() < rule.probability

    # ------------------------------------------------------------------
    # Properties
    # ------------------------------------------------------------------

    @property
    def enabled(self) -> bool:
        return self._enabled

    @property
    def app_name(self) -> str:
        return self._app_name

    @property
    def active_rules(self) -> List[FaultRuleConfig]:
        return self._active_rules


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

def _env_bool(name: str, default: bool) -> bool:
    """Read an environment variable as a boolean."""
    val = os.environ.get(name)
    if val is None:
        return default
    return val.lower() in ("1", "true", "yes", "on")


def _matches_url(pattern: str, url: str) -> bool:
    """Simple glob-style URL pattern matching.

    * Empty pattern matches everything.
    * ``*`` matches a single path segment (no slashes).
    * ``**`` matches any number of path segments.
    """
    if not pattern:
        return True
    if not url:
        return True

    # Convert glob to regex
    regex = (
        pattern.replace(".", r"\.")
        .replace("**", "##DOUBLESTAR##")
        .replace("*", "[^/]*")
        .replace("##DOUBLESTAR##", ".*")
    )
    try:
        return bool(_re.fullmatch(regex, url))
    except _re.error:
        logger.warning("Invalid URL pattern '%s'", pattern)
        return False
