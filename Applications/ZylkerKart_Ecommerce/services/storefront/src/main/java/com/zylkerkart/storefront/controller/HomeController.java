package com.zylkerkart.storefront.controller;

import com.zylkerkart.storefront.service.ApiGateway;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.zip.CRC32;

@Controller
public class HomeController {

    private final ApiGateway api;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public HomeController(ApiGateway api) {
        this.api = api;
    }

    // ─── Page Routes ──────────────────────────────────────────────────────

    /**
     * Landing page — Featured products + categories + more products.
     */
    @GetMapping("/")
    public String index(Model model, HttpSession session) {
        // Use current date+hour as seed so "Top Products" rotates every hour
        String hourKey = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd-HH"));
        CRC32 crc = new CRC32();
        crc.update(hourKey.getBytes());
        long hourlySeed = crc.getValue();
        int topPage = (int) (Math.abs(hourlySeed) % 90);
        int morePage = (int) (Math.abs(hourlySeed + 1) % 90);

        Map<String, Object> products = api.get("product", "/products",
                Map.of("size", "10", "page", String.valueOf(topPage)));
        Map<String, Object> categories = api.get("product", "/products/categories");
        Map<String, Object> moreProducts = api.get("product", "/products",
                Map.of("size", "10", "page", String.valueOf(morePage)));

        model.addAttribute("products", getList(products, "products"));
        model.addAttribute("moreProducts", getList(moreProducts, "products"));
        model.addAttribute("categories", getData(categories));
        model.addAttribute("title", "ZylkerKart - Shop the Best Deals");
        addSessionAttributes(model, session);
        return "pages/home";
    }

    /**
     * Product listing with filters.
     */
    @GetMapping("/products")
    public String products(
            @RequestParam(defaultValue = "0") String page,
            @RequestParam(defaultValue = "20") String size,
            @RequestParam(defaultValue = "") String category,
            @RequestParam(defaultValue = "") String search,
            @RequestParam(defaultValue = "") String sort,
            Model model, HttpSession session) {

        Map<String, String> query = new LinkedHashMap<>();
        query.put("page", page);
        query.put("size", size);
        if (!category.isEmpty()) query.put("category", category);
        if (!search.isEmpty()) query.put("search", search);
        if (!sort.isEmpty()) query.put("sort", sort);

        Map<String, Object> products = api.get("product", "/products", query);
        Map<String, Object> categories = api.get("product", "/products/categories");

        Map<String, String> filters = Map.of(
                "page", page, "size", size,
                "category", category, "search", search, "sort", sort
        );

        Map<String, Object> productData = getDataMap(products);
        model.addAttribute("products", productData);
        model.addAttribute("categories", getData(categories));
        model.addAttribute("filters", filters);
        model.addAttribute("title", "Products - ZylkerKart");

        // Pre-compute pagination values in Java to avoid Thymeleaf SpEL type issues
        int totalPages = safeInt(productData, "totalPages", 0);
        int currentPage = 0;
        try { currentPage = Integer.parseInt(page); } catch (NumberFormatException ignored) {}
        model.addAttribute("totalPages", totalPages);
        model.addAttribute("currentPage", currentPage);

        addSessionAttributes(model, session);
        return "pages/products";
    }

    /**
     * Single product detail page.
     */
    @GetMapping("/products/{id}")
    public String productDetail(@PathVariable long id, Model model, HttpSession session) {
        Map<String, Object> product = api.get("product", "/products/" + id);

        if (safeInt(product, "status", 0) != 200) {
            // 404 page uses the layout decorator, so it needs all layout model attributes
            model.addAttribute("categories", List.of());
            addSessionAttributes(model, session);
            return "error/404";
        }

        Map<String, Object> data = safeMap(product.get("data"));
        String title = safeString(data, "title", "Product")
                + " - " + safeString(data, "productDescription", "ZylkerKart");

        parseJsonStringFields(data);
        model.addAttribute("product", data);
        model.addAttribute("title", title);
        addSessionAttributes(model, session);
        return "pages/product-detail";
    }

    /**
     * Cart page.
     */
    @GetMapping("/cart")
    public String cart(Model model, HttpSession session) {
        String sessionId = session.getId();
        Map<String, Object> cart = api.get("order", "/cart/" + sessionId);

        model.addAttribute("cart", getDataMap(cart));
        model.addAttribute("title", "Cart - ZylkerKart");
        addSessionAttributes(model, session);
        return "pages/cart";
    }

    /**
     * Checkout page.
     */
    @GetMapping("/checkout")
    public String checkout(Model model, HttpSession session) {
        if (session.getAttribute("auth_token") == null) {
            session.setAttribute("redirect", "/checkout");
            return "redirect:/login";
        }

        String sessionId = session.getId();
        Map<String, Object> cart = api.get("order", "/cart/" + sessionId);

        model.addAttribute("cart", getDataMap(cart));
        model.addAttribute("title", "Checkout - ZylkerKart");
        addSessionAttributes(model, session);
        return "pages/checkout";
    }

    /**
     * POST /checkout — Place an order (accepts JSON from frontend JS).
     */
    @PostMapping(value = "/checkout", produces = "application/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> placeOrder(
            @RequestBody Map<String, Object> payload,
            HttpSession session) {

        String token = (String) session.getAttribute("auth_token");
        if (token == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("success", false, "message", "Not authenticated"));
        }

        String sessionId = session.getId();

        // Extract fields sent by the checkout JS
        String fullName = safeString(payload, "fullName", "");
        String phone = safeString(payload, "phone", "");
        String address = safeString(payload, "address", "");
        String email = safeString(payload, "email", "");
        String paymentMethod = safeString(payload, "paymentMethod", "cod");

        // Get user from session for email fallback and userId
        Map<String, Object> user = getSessionUser(session);

        // Fall back to session user email if not provided
        if (email.isEmpty()) {
            email = user != null ? safeString(user, "email", "") : "";
        }

        // Get userId from session user
        Object userId = user != null ? user.get("id") : null;

        Map<String, Object> customer = new HashMap<>();
        customer.put("name", fullName);
        customer.put("email", email);
        customer.put("phone", phone);
        customer.put("address", address);
        customer.put("paymentMethod", paymentMethod);

        Map<String, Object> body = new HashMap<>();
        body.put("sessionId", sessionId);
        body.put("customer", customer);
        if (userId != null) {
            body.put("userId", userId);
        }

        Map<String, Object> order = api.post("order", "/orders", body, token);
        int status = safeInt(order, "status", 0);

        if (status >= 200 && status < 300) {
            Map<String, Object> result = new HashMap<>();
            result.put("success", true);
            result.put("message", "Order placed successfully!");
            result.put("order", order.get("data"));
            return ResponseEntity.ok(result);
        }

        Map<String, Object> errorData = safeMap(order.get("data"));
        String errorMsg = errorData != null
                ? safeString(errorData, "error", "Payment failed. Please try again.")
                : "Payment failed. Please try again.";

        return ResponseEntity.status(status >= 400 ? status : 422)
                .body(Map.of("success", false, "message", errorMsg));
    }

    /**
     * Order history page.
     */
    @GetMapping("/orders")
    public String orderHistory(Model model, HttpSession session) {
        if (session.getAttribute("auth_token") == null) {
            session.setAttribute("redirect", "/orders");
            return "redirect:/login";
        }
        model.addAttribute("title", "My Orders - ZylkerKart");
        addSessionAttributes(model, session);
        return "pages/orders";
    }

    // ─── Cart API Proxies ─────────────────────────────────────────────────

    @PostMapping(value = "/api/cart/add", produces = "application/json")
    @ResponseBody
    public ResponseEntity<Object> apiCartAdd(@RequestBody Map<String, Object> body) {
        Map<String, Object> result = api.post("order", "/cart/add", body);
        return ResponseEntity.status(safeInt(result, "status", 503)).body(result.get("data"));
    }

    @GetMapping(value = "/api/cart/count", produces = "application/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> apiCartCount(
            @RequestParam(required = false) String sessionId,
            HttpSession session) {
        String sid = (sessionId != null && !sessionId.isEmpty()) ? sessionId : session.getId();
        Map<String, Object> result = api.get("order", "/cart/" + sid);
        Map<String, Object> data = safeMap(result.get("data"));
        int itemCount = data != null ? safeInt(data, "itemCount", 0) : 0;
        return ResponseEntity.ok(Map.of("itemCount", itemCount));
    }

    @PutMapping(value = "/api/cart/item", produces = "application/json")
    @ResponseBody
    public ResponseEntity<Object> apiCartUpdate(@RequestBody Map<String, Object> body) {
        String sessionId = safeString(body, "sessionId", "");
        Object productId = body.get("productId");
        Map<String, Object> result = api.put("order",
                "/cart/" + sessionId + "/item/" + productId,
                Map.of("quantity", body.get("quantity")), null);
        return ResponseEntity.status(safeInt(result, "status", 503)).body(result.get("data"));
    }

    @DeleteMapping(value = "/api/cart/item", produces = "application/json")
    @ResponseBody
    public ResponseEntity<Object> apiCartRemove(@RequestBody Map<String, Object> body) {
        String sessionId = safeString(body, "sessionId", "");
        Object productId = body.get("productId");
        Map<String, Object> result = api.delete("order",
                "/cart/" + sessionId + "/item/" + productId);
        return ResponseEntity.status(safeInt(result, "status", 503)).body(result.get("data"));
    }

    // ─── Search API Proxies ───────────────────────────────────────────────

    @GetMapping(value = "/api/search/suggestions", produces = "application/json")
    @ResponseBody
    public ResponseEntity<Object> apiSearchSuggestions(
            @RequestParam(defaultValue = "") String q,
            @RequestParam(defaultValue = "8") String limit) {
        Map<String, Object> result = api.get("search", "/search/suggestions",
                Map.of("q", q, "limit", limit));
        return ResponseEntity.status(safeInt(result, "status", 503)).body(result.get("data"));
    }

    @GetMapping(value = "/api/search/trending", produces = "application/json")
    @ResponseBody
    public ResponseEntity<Object> apiSearchTrending(
            @RequestParam(defaultValue = "10") String limit) {
        Map<String, Object> result = api.get("search", "/search/trending",
                Map.of("limit", limit));
        return ResponseEntity.status(safeInt(result, "status", 503)).body(result.get("data"));
    }

    @PostMapping(value = "/api/search/log", produces = "application/json")
    @ResponseBody
    public ResponseEntity<Object> apiSearchLog(@RequestBody Map<String, Object> body, HttpSession session) {
        Map<String, Object> logBody = new HashMap<>(body);
        logBody.putIfAbsent("sessionId", session.getId());
        logBody.putIfAbsent("resultsCount", 0);
        Map<String, Object> result = api.post("search", "/search/log", logBody);
        return ResponseEntity.status(safeInt(result, "status", 503)).body(result.get("data"));
    }

    // ─── Orders API ───────────────────────────────────────────────────────

    @GetMapping(value = "/api/orders", produces = "application/json")
    @ResponseBody
    public ResponseEntity<Object> apiOrders(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "10") int perPage,
            HttpSession session) {

        String token = (String) session.getAttribute("auth_token");
        Map<String, Object> user = getSessionUser(session);
        if (token == null || user == null) {
            return ResponseEntity.status(401).body(Map.of("error", "Not authenticated"));
        }

        Object userId = user.get("id");
        if (userId == null) {
            return ResponseEntity.ok(Map.of("orders", List.of()));
        }

        Map<String, Object> result = api.get("order", "/orders/user/" + userId,
                null, token);
        Object data = result.get("data");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> rawOrders = data instanceof List ? (List<Map<String, Object>>) data : new ArrayList<>();

        // Fallback: also look up by session if user-based returned nothing
        if (rawOrders.isEmpty()) {
            String sessionId = session.getId();
            Map<String, Object> sessionResult = api.get("order", "/orders/session/" + sessionId,
                    null, token);
            Object sessionData = sessionResult.get("data");
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> sessionOrders = sessionData instanceof List
                    ? (List<Map<String, Object>>) sessionData : new ArrayList<>();
            rawOrders.addAll(sessionOrders);
        }

        // Transform fields from order service — handle both snake_case and camelCase
        List<Map<String, Object>> orders = new ArrayList<>();
        for (Map<String, Object> raw : rawOrders) {
            Map<String, Object> order = new LinkedHashMap<>();
            order.put("orderId", raw.get("id"));
            order.put("status", raw.get("status"));
            order.put("totalAmount", getFlexKey(raw, "total_amount", "totalAmount"));
            order.put("createdAt", getFlexKey(raw, "created_at", "createdAt"));
            order.put("shippingAddress", getFlexKey(raw, "shipping_address", "shippingAddress"));
            order.put("customerName", getFlexKey(raw, "customer_name", "customerName"));

            // Transform items
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> rawItems = raw.get("items") instanceof List
                    ? (List<Map<String, Object>>) raw.get("items") : new ArrayList<>();
            List<Map<String, Object>> items = new ArrayList<>();
            for (Map<String, Object> ri : rawItems) {
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("title", getFlexKey(ri, "product_title", "productTitle"));
                item.put("quantity", ri.get("quantity"));
                item.put("price", getFlexKey(ri, "unit_price", "unitPrice"));
                item.put("image", getFlexKey(ri, "image_url", "imageUrl"));
                item.put("size", ri.get("size"));
                items.add(item);
            }
            order.put("items", items);

            // Enrich with payment data
            Object orderId = raw.get("id");
            if (orderId != null) {
                try {
                    Map<String, Object> txnResult = api.get("payment", "/payments/order/" + orderId);
                    Object txnData = txnResult.get("data");
                    if (txnData instanceof Map) {
                        @SuppressWarnings("unchecked")
                        Map<String, Object> txn = (Map<String, Object>) txnData;
                        order.put("transactionId", txn.getOrDefault("transaction_ref", txn.get("transactionRef")));
                        order.put("paymentMethod", txn.getOrDefault("method", txn.get("paymentMethod")));
                        order.put("paymentStatus", txn.getOrDefault("status", txn.get("paymentStatus")));
                    } else if (txnData instanceof List) {
                        @SuppressWarnings("unchecked")
                        List<Map<String, Object>> txns = (List<Map<String, Object>>) txnData;
                        if (!txns.isEmpty()) {
                            Map<String, Object> txn = txns.get(0);
                            order.put("transactionId", txn.getOrDefault("transaction_ref", txn.get("transactionRef")));
                            order.put("paymentMethod", txn.getOrDefault("method", txn.get("paymentMethod")));
                            order.put("paymentStatus", txn.getOrDefault("status", txn.get("paymentStatus")));
                        }
                    }
                } catch (Exception e) {
                    // Skip payment enrichment on error
                }
            }

            orders.add(order);
        }

        // Pagination
        int safePerPage = Math.max(1, Math.min(perPage, 50));
        int total = orders.size();
        int totalPages = Math.max(1, (int) Math.ceil((double) total / safePerPage));
        int safePage = Math.max(1, page);
        int offset = (safePage - 1) * safePerPage;
        List<Map<String, Object>> paginatedOrders = orders.subList(
                Math.min(offset, total),
                Math.min(offset + safePerPage, total));

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("orders", paginatedOrders);
        response.put("page", safePage);
        response.put("totalPages", totalPages);
        response.put("totalOrders", total);
        return ResponseEntity.ok(response);
    }

    // ─── Health Check ─────────────────────────────────────────────────────

    @GetMapping(value = "/health", produces = "application/json")
    @ResponseBody
    public Map<String, Object> health() {
        return Map.of(
                "service", "storefront",
                "status", "UP",
                "timestamp", LocalDateTime.now().toString()
        );
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    private void addSessionAttributes(Model model, HttpSession session) {
        model.addAttribute("sessionId", session.getId());
        model.addAttribute("user", session.getAttribute("user"));
        model.addAttribute("authToken", session.getAttribute("auth_token"));
    }

    /**
     * Safely extract an int from a map value, avoiding NullPointerException on unboxing.
     */
    private int safeInt(Map<String, Object> map, String key, int defaultValue) {
        Object val = map.get(key);
        if (val instanceof Number) return ((Number) val).intValue();
        if (val instanceof String) {
            try { return Integer.parseInt((String) val); } catch (NumberFormatException ignored) {}
        }
        return defaultValue;
    }

    /**
     * Safely extract a String from a map value, avoiding ClassCastException.
     */
    private String safeString(Map<String, Object> map, String key, String defaultValue) {
        Object val = map.get(key);
        if (val instanceof String) return (String) val;
        if (val != null) return String.valueOf(val);
        return defaultValue;
    }

    /**
     * Safely cast an object to Map, returning null if not a Map.
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> safeMap(Object obj) {
        return obj instanceof Map ? (Map<String, Object>) obj : null;
    }

    /**
     * Safely retrieve the user map from session, guarding against Redis deserialization issues.
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> getSessionUser(HttpSession session) {
        Object user = session.getAttribute("user");
        return user instanceof Map ? (Map<String, Object>) user : null;
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> getList(Map<String, Object> result, String key) {
        Object rawData = result.get("data");
        Map<String, Object> data = rawData instanceof Map ? (Map<String, Object>) rawData : null;
        if (data == null) return List.of();
        Object list = data.get(key);
        return list instanceof List ? (List<Map<String, Object>>) list : List.of();
    }

    /**
     * Parse JSON-encoded string values in a product map into proper objects.
     * The product API returns some fields (productDetails, deliveryOptions, etc.) as JSON strings.
     * On parse failure, wraps raw strings in a fallback map to prevent Thymeleaf SpEL errors.
     */
    private void parseJsonStringFields(Map<String, Object> data) {
        if (data == null) return;
        String[] jsonFields = {"productDetails", "deliveryOptions", "specifications",
                "whatCustomersSaid", "offers", "starRating", "sizes"};
        for (String field : jsonFields) {
            Object val = data.get(field);
            if (val instanceof String) {
                String str = ((String) val).trim();
                if ((str.startsWith("{") || str.startsWith("[")) && str.length() > 1) {
                    try {
                        data.put(field, objectMapper.readValue(str, Object.class));
                    } catch (JsonProcessingException e) {
                        // Wrap raw string in a fallback structure to prevent Thymeleaf SpEL errors
                        // on nested access like product['productDetails']['description']
                        if (field.equals("productDetails")) {
                            Map<String, Object> fallback = new HashMap<>();
                            fallback.put("description", str);
                            data.put(field, fallback);
                        }
                        // For list-type fields, replace with empty list to prevent character iteration
                        if (field.equals("sizes") || field.equals("deliveryOptions") ||
                                field.equals("specifications") || field.equals("whatCustomersSaid") ||
                                field.equals("offers")) {
                            data.put(field, List.of());
                        }
                    }
                }
            }
        }
    }

    /**
     * Extract data from API result, returning only Lists (safe for th:each).
     * When a service is down, ApiGateway returns {"error": "..."} — a Map, not a List.
     * Passing that Map to Thymeleaf's th:each iterates over Map.Entry objects,
     * causing SpEL errors mid-render and ERR_INCOMPLETE_CHUNKED_ENCODING.
     */
    @SuppressWarnings("unchecked")
    private Object getData(Map<String, Object> result) {
        Object data = result.get("data");
        if (data instanceof List) return data;
        return List.of();
    }

    /**
     * Extract data as Map from API result, only on successful responses.
     * On error (status >= 300 or service down), returns empty Map so templates
     * get null for missing keys and degrade gracefully instead of crashing mid-render.
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> getDataMap(Map<String, Object> result) {
        int status = safeInt(result, "status", 0);
        Object data = result.get("data");
        if (status >= 200 && status < 300 && data instanceof Map) {
            return (Map<String, Object>) data;
        }
        return Map.of();
    }

    /**
     * Get a value from a map trying both snake_case and camelCase keys.
     * Handles the mismatch between order-service response format and frontend expectations.
     */
    private Object getFlexKey(Map<String, Object> map, String snakeCase, String camelCase) {
        Object val = map.get(snakeCase);
        return val != null ? val : map.get(camelCase);
    }
}
