package com.zylkerkart.product.controller;

import com.zylkerkart.product.dto.CategoryDTO;
import com.zylkerkart.product.dto.ProductDTO;
import com.zylkerkart.product.service.ProductService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/products")
public class ProductController {

    @Autowired
    private ProductService productService;

    /**
     * GET /products - Paginated product listing with optional filters
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> listProducts(
            @RequestParam(required = false) String category,
            @RequestParam(required = false) String subcategory,
            @RequestParam(required = false) String search,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) String sort) {

        Map<String, Object> response = productService.listProducts(category, subcategory, search, page, size, sort);
        return ResponseEntity.ok(response);
    }

    /**
     * GET /products/categories - List all category groups with subcategories
     */
    @GetMapping("/categories")
    public ResponseEntity<List<CategoryDTO>> getCategories() {
        return ResponseEntity.ok(productService.getCategories());
    }

    /**
     * GET /products/{id} - Get single product detail
     */
    @GetMapping("/{id}")
    public ResponseEntity<ProductDTO> getProduct(@PathVariable Long id) {
        ProductDTO product = productService.getProduct(id);
        if (product == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(product);
    }
}
