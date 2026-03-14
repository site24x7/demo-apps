import os
import time
import mysql.connector
from mysql.connector import pooling
import logging

logger = logging.getLogger(__name__)

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "mysql"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", "ZylkerKart@2024"),
    "database": os.getenv("DB_NAME", "db_payment"),
    "charset": "utf8mb4",
    "collation": "utf8mb4_unicode_ci",
}

_pool = None


def get_pool():
    global _pool
    if _pool is None:
        for attempt in range(30):
            try:
                _pool = pooling.MySQLConnectionPool(
                    pool_name="payment_pool",
                    pool_size=10,
                    pool_reset_session=True,
                    **DB_CONFIG,
                )
                logger.info(
                    f"Connected to MySQL ({DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']})"
                )
                return _pool
            except Exception as e:
                logger.warning(f"Waiting for MySQL... attempt {attempt + 1}/30: {e}")
                time.sleep(2)
        raise RuntimeError("Could not connect to MySQL after 30 attempts")
    return _pool


def get_connection():
    return get_pool().get_connection()
