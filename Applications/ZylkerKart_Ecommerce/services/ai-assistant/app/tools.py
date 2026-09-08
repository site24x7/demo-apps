"""HTTP tools that fetch live catalog / cart / order / search data."""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx
from traceloop.sdk.decorators import tool

logger = logging.getLogger(__name__)

PRODUCT_URL = os.environ.get("PRODUCT_SERVICE_URL", "http://product-service:8081")
ORDER_URL = os.environ.get("ORDER_SERVICE_URL", "http://order-service:8082")
SEARCH_URL = os.environ.get("SEARCH_SERVICE_URL", "http://search-service:8083")
TIMEOUT = float(os.environ.get("TOOL_HTTP_TIMEOUT", "12"))


def _get(url: str, params: dict[str, Any] | None = None) -> Any:
    with httpx.Client(timeout=TIMEOUT) as client:
        resp = client.get(url, params=params)
        resp.raise_for_status()
        return resp.json()


@tool(name="search_products")
def search_products(
    query: str = "",
    category: str | None = None,
    max_price: float | None = None,
    size: int = 8,
) -> dict[str, Any]:
    params: dict[str, Any] = {"page": 0, "size": size}
    if query:
        params["search"] = query
    if category:
        params["category"] = category
    data = _get(f"{PRODUCT_URL}/products", params)
    products = data.get("products", data if isinstance(data, list) else [])
    if max_price is not None:
        filtered = []
        for p in products:
            try:
                price_raw = p.get("initialPrice") or p.get("finalPrice") or 0
                if isinstance(price_raw, str):
                    price_raw = float(
                        "".join(c for c in price_raw if c.isdigit() or c == ".")
                        or "0"
                    )
                if float(price_raw) <= float(max_price):
                    filtered.append(p)
            except (TypeError, ValueError):
                filtered.append(p)
        products = filtered
    return {
        "products": products[:size],
        "totalItems": data.get("totalItems", len(products)) if isinstance(data, dict) else len(products),
    }


@tool(name="get_product")
def get_product(product_id: int) -> dict[str, Any]:
    return _get(f"{PRODUCT_URL}/products/{product_id}")


@tool(name="get_cart")
def get_cart(session_id: str) -> dict[str, Any]:
    if not session_id:
        return {"items": [], "itemCount": 0, "totalAmount": 0, "error": "missing session_id"}
    return _get(f"{ORDER_URL}/cart/{session_id}")


@tool(name="get_user_orders")
def get_user_orders(user_id: str | int) -> dict[str, Any]:
    if user_id is None or user_id == "":
        return {"orders": [], "error": "User not logged in"}
    orders = _get(f"{ORDER_URL}/orders/user/{user_id}")
    if isinstance(orders, list):
        return {"orders": orders[:10]}
    return {"orders": orders}


@tool(name="get_trending")
def get_trending(limit: int = 10) -> dict[str, Any]:
    return _get(f"{SEARCH_URL}/search/trending", {"limit": limit})


TOOL_DEFINITIONS = [
    {
        "type": "function",
        "function": {
            "name": "search_products",
            "description": "Search the ZylkerKart product catalog by keyword, optional category, and optional max price.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search keywords"},
                    "category": {"type": "string", "description": "Category group name"},
                    "max_price": {"type": "number", "description": "Maximum price filter"},
                    "size": {"type": "integer", "description": "Max results (default 8)"},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_product",
            "description": "Get full details for a single product by productId.",
            "parameters": {
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer"},
                },
                "required": ["product_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_cart",
            "description": "Get the shopper's current cart contents for their session.",
            "parameters": {
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                },
                "required": ["session_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_user_orders",
            "description": "List recent orders for a logged-in user.",
            "parameters": {
                "type": "object",
                "properties": {
                    "user_id": {"type": "string", "description": "Authenticated user id"},
                },
                "required": ["user_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_trending",
            "description": "Get trending search queries on ZylkerKart.",
            "parameters": {
                "type": "object",
                "properties": {
                    "limit": {"type": "integer"},
                },
            },
        },
    },
]


def execute_tool(name: str, args: dict[str, Any], context: dict[str, Any]) -> Any:
    try:
        if name == "search_products":
            return search_products(
                query=args.get("query", ""),
                category=args.get("category"),
                max_price=args.get("max_price"),
                size=int(args.get("size", 8)),
            )
        if name == "get_product":
            return get_product(int(args["product_id"]))
        if name == "get_cart":
            sid = args.get("session_id") or context.get("session_id") or ""
            return get_cart(sid)
        if name == "get_user_orders":
            uid = args.get("user_id") or context.get("user_id") or ""
            return get_user_orders(uid)
        if name == "get_trending":
            return get_trending(int(args.get("limit", 10)))
        return {"error": f"Unknown tool: {name}"}
    except Exception as e:
        logger.exception("Tool %s failed", name)
        return {"error": str(e)}


def build_cards(tool_name: str, result: Any) -> list[dict[str, Any]]:
    cards: list[dict[str, Any]] = []
    if not isinstance(result, dict) or result.get("error"):
        return cards

    if tool_name == "search_products":
        for p in result.get("products") or []:
            images = p.get("images") or []
            cards.append(
                {
                    "type": "product",
                    "productId": p.get("productId"),
                    "title": p.get("title"),
                    "price": p.get("finalPrice") or p.get("initialPrice"),
                    "image": images[0] if images else None,
                    "rating": p.get("rating"),
                    "url": f"/products/{p.get('productId')}",
                }
            )
    elif tool_name == "get_product" and result.get("productId"):
        images = result.get("images") or []
        cards.append(
            {
                "type": "product",
                "productId": result.get("productId"),
                "title": result.get("title"),
                "price": result.get("finalPrice") or result.get("initialPrice"),
                "image": images[0] if images else None,
                "rating": result.get("rating"),
                "url": f"/products/{result.get('productId')}",
            }
        )
    elif tool_name == "get_cart":
        for item in result.get("items") or []:
            cards.append(
                {
                    "type": "cart_item",
                    "productId": item.get("productId"),
                    "title": item.get("title"),
                    "price": item.get("price"),
                    "quantity": item.get("quantity"),
                    "image": item.get("image"),
                    "url": f"/products/{item.get('productId')}" if item.get("productId") else "/cart",
                }
            )
        if result.get("itemCount") is not None:
            cards.append(
                {
                    "type": "cart_summary",
                    "itemCount": result.get("itemCount"),
                    "totalAmount": result.get("totalAmount"),
                    "url": "/cart",
                }
            )
    elif tool_name == "get_user_orders":
        for o in result.get("orders") or []:
            cards.append(
                {
                    "type": "order",
                    "orderId": o.get("id") or o.get("orderId"),
                    "status": o.get("status"),
                    "totalAmount": o.get("total_amount") or o.get("totalAmount"),
                    "createdAt": o.get("created_at") or o.get("createdAt"),
                    "url": "/orders",
                }
            )
    elif tool_name == "get_trending":
        for t in result.get("trending") or []:
            cards.append(
                {
                    "type": "trending",
                    "query": t.get("query"),
                    "count": t.get("count"),
                    "url": f"/products?search={t.get('query', '')}",
                }
            )
    return cards