"""
Site24x7 Labs Chaos SDK for Python.

Inject realistic application-level faults into Flask and FastAPI
microservices for chaos engineering demos.

Usage:
    # Flask
    from site24x7_chaos.flask import init_chaos
    app = Flask(__name__)
    init_chaos(app)

    # FastAPI
    from site24x7_chaos.fastapi import init_chaos
    app = FastAPI()
    init_chaos(app)

Environment variables:
    CHAOS_SDK_ENABLED   - Enable/disable the SDK (default: true)
    CHAOS_SDK_APP_NAME  - Application name matching the server config
    CHAOS_SDK_CONFIG_DIR - Path to config directory (default: /var/site24x7-labs/faults)
"""

__version__ = "1.0.0"
