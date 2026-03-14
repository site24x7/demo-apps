"""Daemon threads for config file watching and heartbeat writing.

When a change is detected (via file modification time), the file is re-parsed
and the new AppFaultConfig is passed to the registered listener callback.

The HeartbeatWriter periodically writes a small JSON file that the agent
reads to discover which SDKs are installed and active.
"""

from __future__ import annotations

import json
import logging
import os
import platform
import threading
import time
from pathlib import Path
from typing import Callable, Optional

from .models import AppFaultConfig

logger = logging.getLogger("site24x7_chaos.config")

_HEARTBEAT_INTERVAL_S = 30.0


class ConfigFileWatcher:
    """Polls a JSON fault-config file on disk and notifies a listener on change.

    The agent writes config files to ``{config_dir}/{app_name}.json`` via
    atomic rename.  This watcher checks the file's mtime every
    *poll_interval_s* seconds and re-parses only when it changes.
    """

    def __init__(
        self,
        config_file: str,
        listener: Callable[[AppFaultConfig], None],
        poll_interval_s: float = 2.0,
    ) -> None:
        self._config_path = Path(config_file)
        self._listener = listener
        self._poll_interval = poll_interval_s
        self._last_mtime: float = 0.0
        self._running = False
        self._thread: Optional[threading.Thread] = None

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the background polling daemon thread."""
        if self._thread is not None and self._thread.is_alive():
            logger.warning("ConfigFileWatcher is already running")
            return

        self._running = True
        self._thread = threading.Thread(
            target=self._run,
            name="chaos-config-watcher",
            daemon=True,
        )
        self._thread.start()
        logger.info("ConfigFileWatcher started, watching: %s", self._config_path)

    def stop(self) -> None:
        """Signal the watcher thread to stop."""
        self._running = False
        if self._thread is not None:
            self._thread.join(timeout=self._poll_interval + 1)
            self._thread = None
        logger.info("ConfigFileWatcher stopped")

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _run(self) -> None:
        while self._running:
            try:
                self._check_for_changes()
            except Exception:
                logger.warning("Error checking config file", exc_info=True)
            time.sleep(self._poll_interval)

    def _check_for_changes(self) -> None:
        if not self._config_path.exists():
            # File doesn't exist — either agent hasn't written it yet,
            # or agent deleted it (all rules removed). If we had rules
            # before, clear them by sending an empty config.
            if self._last_mtime > 0.0:
                self._last_mtime = 0.0
                logger.info("Config file removed, clearing all rules")
                try:
                    self._listener(AppFaultConfig())
                except Exception:
                    logger.error("Config update listener error on clear", exc_info=True)
            return

        try:
            current_mtime = self._config_path.stat().st_mtime
        except OSError:
            return

        if current_mtime <= self._last_mtime:
            return

        self._last_mtime = current_mtime

        try:
            content = self._config_path.read_text(encoding="utf-8")
            data = json.loads(content)
            config = AppFaultConfig.from_dict(data)
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            logger.warning("Failed to parse config file %s: %s", self._config_path, exc)
            return
        except OSError as exc:
            logger.warning("Failed to read config file %s: %s", self._config_path, exc)
            return

        logger.info(
            "Config file changed, loaded %d rules",
            len(config.rules),
        )
        try:
            self._listener(config)
        except Exception:
            logger.error("Config update listener error", exc_info=True)


class HeartbeatWriter:
    """Periodically writes a ``{app_name}.heartbeat.json`` file so the agent
    can detect that this SDK is installed and running.

    The heartbeat file contains:
    - ``app_name``   – matches the config filename stem
    - ``sdk_version``
    - ``sdk_language`` – always ``"python"``
    - ``framework``   – e.g. ``"flask"`` / ``"fastapi"``
    - ``framework_version``
    - ``pid``
    - ``timestamp``  – ISO-8601 UTC
    """

    def __init__(
        self,
        config_dir: str,
        app_name: str,
        sdk_version: str,
        framework: str = "",
        framework_version: str = "",
        interval_s: float = _HEARTBEAT_INTERVAL_S,
    ) -> None:
        self._heartbeat_path = Path(config_dir) / f"{app_name}.heartbeat.json"
        self._app_name = app_name
        self._sdk_version = sdk_version
        self._framework = framework
        self._framework_version = framework_version
        self._interval = interval_s
        self._running = False
        self._thread: Optional[threading.Thread] = None

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._running = True
        self._thread = threading.Thread(
            target=self._run,
            name="chaos-heartbeat-writer",
            daemon=True,
        )
        self._thread.start()
        logger.info("HeartbeatWriter started, path: %s", self._heartbeat_path)

    def stop(self) -> None:
        self._running = False
        if self._thread is not None:
            self._thread.join(timeout=self._interval + 1)
            self._thread = None
        # Remove heartbeat file on clean shutdown
        try:
            self._heartbeat_path.unlink(missing_ok=True)
        except OSError:
            pass
        logger.info("HeartbeatWriter stopped")

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _run(self) -> None:
        # Write immediately on start, then periodically
        while self._running:
            try:
                self._write_heartbeat()
            except Exception:
                logger.warning("Error writing heartbeat file", exc_info=True)
            time.sleep(self._interval)

    def _write_heartbeat(self) -> None:
        data = {
            "app_name": self._app_name,
            "sdk_version": self._sdk_version,
            "sdk_language": "python",
            "framework": self._framework,
            "framework_version": self._framework_version,
            "pid": os.getpid(),
            "hostname": platform.node(),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        # Atomic write: write to tmp then rename
        tmp_path = self._heartbeat_path.with_suffix(".tmp")
        tmp_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
        tmp_path.replace(self._heartbeat_path)
