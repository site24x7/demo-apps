"""asyncpg pool with background startup retry and lazy reconnection."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any

import asyncpg

from app.config import Settings

logger = logging.getLogger("db")

_CONNECTIVITY_ERRORS: tuple[type[BaseException], ...] = (
    OSError,
    asyncio.TimeoutError,
    asyncpg.PostgresConnectionError,
    asyncpg.InterfaceError,
    asyncpg.CannotConnectNowError,
)


class DatabaseUnavailable(RuntimeError):
    """Raised when PostgreSQL cannot be reached."""


async def _init_connection(conn: asyncpg.Connection) -> None:
    # json/jsonb <-> python objects
    for typ in ("json", "jsonb"):
        await conn.set_type_codec(
            typ, encoder=json.dumps, decoder=json.loads, schema="pg_catalog"
        )


class Database:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.pool: asyncpg.Pool | None = None
        self._lock = asyncio.Lock()
        self._last_attempt = 0.0
        self.last_error: str | None = None

    # ── connection management ────────────────────────────────────────────
    async def _create_pool(self) -> asyncpg.Pool:
        s = self.settings
        return await asyncpg.create_pool(
            host=s.db_host,
            port=s.db_port,
            user=s.db_user,
            password=s.db_password,
            database=s.db_name,
            min_size=s.db_pool_min,
            max_size=s.db_pool_max,
            timeout=s.db_connect_timeout,
            command_timeout=15,
            init=_init_connection,
        )

    async def try_connect(self) -> bool:
        """Single connection attempt (no-op if already connected)."""
        if self.pool is not None:
            return True
        async with self._lock:
            if self.pool is not None:
                return True
            self._last_attempt = time.monotonic()
            try:
                self.pool = await asyncio.wait_for(
                    self._create_pool(), timeout=self.settings.db_connect_timeout + 2
                )
                self.last_error = None
                logger.info(
                    "Connected to PostgreSQL %s:%s/%s",
                    self.settings.db_host,
                    self.settings.db_port,
                    self.settings.db_name,
                )
                return True
            except Exception as exc:  # noqa: BLE001
                self.last_error = f"{type(exc).__name__}: {exc}"
                return False

    async def connect_with_retry(
        self, stop: asyncio.Event | None = None, max_backoff: float = 10.0
    ) -> None:
        """Retry (exponential backoff, capped) until the pool is up or ``stop`` is set."""
        attempt = 0
        delay = 1.0
        while not (stop and stop.is_set()):
            attempt += 1
            if await self.try_connect():
                return
            logger.warning(
                "Waiting for PostgreSQL (attempt %d, retry in %.0fs): %s",
                attempt,
                delay,
                self.last_error,
            )
            try:
                if stop is None:
                    await asyncio.sleep(delay)
                else:
                    await asyncio.wait_for(stop.wait(), timeout=delay)
            except asyncio.TimeoutError:
                pass
            delay = min(delay * 2, max_backoff)

    async def close(self) -> None:
        pool, self.pool = self.pool, None
        if pool is not None:
            try:
                await asyncio.wait_for(pool.close(), timeout=5)
            except Exception:  # noqa: BLE001
                pool.terminate()

    async def _require_pool(self) -> asyncpg.Pool:
        if self.pool is None:
            # lazy reconnect, rate-limited so a dead DB doesn't stall every request
            if time.monotonic() - self._last_attempt >= 2.0:
                await self.try_connect()
            if self.pool is None:
                raise DatabaseUnavailable(self.last_error or "PostgreSQL not connected")
        return self.pool

    async def ping(self) -> bool:
        try:
            pool = await self._require_pool()
            await asyncio.wait_for(pool.fetchval("SELECT 1"), timeout=2)
            return True
        except Exception as exc:  # noqa: BLE001
            self.last_error = f"{type(exc).__name__}: {exc}"
            return False

    # ── query helpers (translate connectivity errors) ────────────────────
    async def _run(self, method: str, query: str, *args: Any) -> Any:
        pool = await self._require_pool()
        try:
            return await getattr(pool, method)(query, *args)
        except _CONNECTIVITY_ERRORS as exc:
            self.last_error = f"{type(exc).__name__}: {exc}"
            raise DatabaseUnavailable(self.last_error) from exc

    async def fetch(self, query: str, *args: Any) -> list[asyncpg.Record]:
        return await self._run("fetch", query, *args)

    async def fetchrow(self, query: str, *args: Any) -> asyncpg.Record | None:
        return await self._run("fetchrow", query, *args)

    async def fetchval(self, query: str, *args: Any) -> Any:
        return await self._run("fetchval", query, *args)

    async def execute(self, query: str, *args: Any) -> str:
        return await self._run("execute", query, *args)


_db_instance: Database | None = None


def get_db(settings: Settings | None = None) -> Database:
    global _db_instance
    if _db_instance is None:
        if settings is None:
            from app.config import get_settings

            settings = get_settings()
        _db_instance = Database(settings)
    return _db_instance


def set_db(db: Database | None) -> None:
    global _db_instance
    _db_instance = db

