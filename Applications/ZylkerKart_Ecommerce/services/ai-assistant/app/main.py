"""ZylkerKart AI shopping assistant — FastAPI entrypoint."""

from __future__ import annotations

import hmac
import json
import logging
import os
from typing import Any, Iterator

import httpx
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.instrumentation import init_tracing

# Initialize Site24x7 / Traceloop BEFORE importing LLM-backed agent
init_tracing()

from app.agent import run_shopping_assistant  # noqa: E402
from app.llm import available_providers, clear_provider_cache, get_provider  # noqa: E402
from app.llm.base import LLMError  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("ai-assistant")

app = FastAPI(title="ZylkerKart AI Assistant", version="1.2.0")

INTERNAL_TOKEN = os.environ.get("AI_INTERNAL_TOKEN", "").strip()


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=4000)
    session_id: str | None = None
    user_id: str | int | None = None
    page_context: str | None = None


class ChatResponse(BaseModel):
    reply: str
    cards: list[dict[str, Any]] = []
    tools_used: list[str] = []
    model: str | None = None
    provider: str | None = None


def _require_internal(x_internal_token: str | None) -> None:
    """Only the storefront (or other trusted callers) may invoke /chat."""
    if not INTERNAL_TOKEN:
        logger.error("AI_INTERNAL_TOKEN is not configured — refusing chat requests")
        raise HTTPException(status_code=503, detail="AI service is not configured")
    provided = (x_internal_token or "").strip()
    if not provided or not hmac.compare_digest(provided, INTERNAL_TOKEN):
        raise HTTPException(status_code=401, detail="Unauthorized")


def _probe_provider() -> dict[str, Any]:
    """Best-effort readiness probe for the configured LLM backend."""
    out: dict[str, Any] = {"reachable": False}
    try:
        provider = get_provider()
        out["provider"] = provider.name
        out["model"] = provider.model
    except LLMError as e:
        out["error"] = str(e)
        return out

    name = provider.name
    if name == "ollama":
        base = (
            os.environ.get("LLM_BASE_URL")
            or os.environ.get("OLLAMA_BASE_URL")
            or "http://host.docker.internal:11434"
        ).rstrip("/")
        if base.endswith("/v1"):
            base = base[:-3]
        try:
            r = httpx.get(f"{base}/api/tags", timeout=3.0)
            out["reachable"] = r.status_code == 200
            out["probe"] = f"{base}/api/tags"
            out["status_code"] = r.status_code
        except Exception as e:
            out["error"] = str(e)
            out["probe"] = f"{base}/api/tags"
    else:
        # Non-Ollama: treat successful provider construction as ready
        out["reachable"] = True
    return out


# Site24x7 Labs Chaos SDK (same pattern as payment-service)
try:
    from site24x7_chaos.fastapi import init_chaos

    init_chaos(
        app,
        app_name=os.getenv("CHAOS_SDK_APP_NAME", "ai-assistant"),
        config_dir=os.getenv("CHAOS_SDK_CONFIG_DIR", "/var/site24x7-labs/faults"),
        enabled=os.getenv("CHAOS_SDK_ENABLED", "true").lower() != "false",
    )
except Exception as e:
    logger.warning("Failed to initialize Chaos SDK: %s", e)


@app.get("/health")
def health() -> dict[str, Any]:
    info: dict[str, Any] = {
        "status": "ok",
        "service": "ai-assistant",
        "providers": available_providers(),
    }
    probe = _probe_provider()
    info["llm"] = probe
    if not probe.get("reachable"):
        info["status"] = "degraded"
    return info


@app.post("/reload")
def reload_provider(
    x_internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
) -> dict[str, Any]:
    _require_internal(x_internal_token)
    clear_provider_cache()
    try:
        provider = get_provider(force_reload=True)
        return {"ok": True, "provider": provider.name, "model": provider.model}
    except LLMError as e:
        return {"ok": False, "error": str(e)}


@app.post("/chat", response_model=ChatResponse)
def chat(
    req: ChatRequest,
    x_internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
) -> ChatResponse:
    _require_internal(x_internal_token)
    logger.info(
        "chat message_len=%s session=%s user=%s",
        len(req.message),
        bool(req.session_id),
        bool(req.user_id),
    )
    result = run_shopping_assistant(
        message=req.message,
        session_id=req.session_id or "",
        user_id=req.user_id,
        page_context=req.page_context,
    )
    return ChatResponse(**result)


@app.post("/chat/stream")
def chat_stream(
    req: ChatRequest,
    x_internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
) -> StreamingResponse:
    """SSE stream of progress events, then a final result payload."""
    _require_internal(x_internal_token)

    def event_gen() -> Iterator[str]:
        import queue
        import threading

        q: queue.Queue[tuple[str, dict[str, Any]] | None] = queue.Queue()

        def on_progress(event: str, data: dict[str, Any]) -> None:
            q.put((event, data))

        def worker() -> None:
            try:
                result = run_shopping_assistant(
                    message=req.message,
                    session_id=req.session_id or "",
                    user_id=req.user_id,
                    page_context=req.page_context,
                    on_progress=on_progress,
                )
                q.put(("final", result))
            except Exception as e:
                logger.exception("chat stream failed")
                q.put(("error", {"error": str(e)}))
            finally:
                q.put(None)

        threading.Thread(target=worker, daemon=True).start()
        while True:
            item = q.get()
            if item is None:
                break
            event, data = item
            yield f"event: {event}\ndata: {json.dumps(data)}\n\n"

    return StreamingResponse(event_gen(), media_type="text/event-stream")
