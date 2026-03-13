package com.zylkerkart.product.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.zylkerkart.product.dto.CategoryDTO;
import com.zylkerkart.product.dto.ProductDTO;
import com.zylkerkart.product.model.*;
import com.zylkerkart.product.repository.CategoryGroupRepository;
import com.zylkerkart.product.repository.ProductRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class ProductService {

    private static final Logger log = LoggerFactory.getLogger(ProductService.class);
    private static final String PRODUCT_CACHE_PREFIX = "product:";
    private static final Duration PRODUCT_CACHE_TTL = Duration.ofMinutes(10);

    @Autowired
    private ProductRepository productRepository;

    @Autowired
    private CategoryGroupRepository categoryGroupRepository;

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    @Autowired
    private ObjectMapper objectMapper;

    /**
     * Get a single product by ID with Redis caching.
     * Check Redis first; if miss, fetch from DB and cache for 10 minutes.
     */
    @Transactional(readOnly = true)
    public ProductDTO getProduct(Long productId) {
        String cacheKey = PRODUCT_CACHE_PREFIX + productId;

        // Check Redis cache first
        try {
            Object cached = redisTemplate.opsForValue().get(cacheKey);
            if (cached != null) {
                log.info("Cache HIT for product: {}", productId);
                if (cached instanceof ProductDTO) {
                    return (ProductDTO) cached;
                }
                // Handle case where Redis returns a LinkedHashMap
                String json = objectMapper.writeValueAsString(cached);
                return objectMapper.readValue(json, ProductDTO.class);
            }
        } catch (Exception e) {
            log.warn("Redis cache read failed for product {}: {}", productId, e.getMessage());
        }

        log.info("Cache MISS for product: {}. Fetching from DB.", productId);

        // Fetch from database
        Optional<Product> optProduct = productRepository.findByProductId(productId);
        if (optProduct.isEmpty()) {
            return null;
        }

        ProductDTO dto = convertToDTO(optProduct.get());

        // Store in Redis cache
        try {
            redisTemplate.opsForValue().set(cacheKey, dto, PRODUCT_CACHE_TTL);
            log.info("Cached product {} in Redis (TTL: {} min)", productId, PRODUCT_CACHE_TTL.toMinutes());
        } catch (Exception e) {
            log.warn("Redis cache write failed for product {}: {}", productId, e.getMessage());
        }

        return dto;
    }

    /**
     * List products with pagination, optional category filter and search.
     */
    @Cacheable(value = "productList", key = "#category + '-' + #subcategory + '-' + #search + '-' + #page + '-' + #size + '-' + #sort")
    public Map<String, Object> listProducts(String category, String subcategory, String search,
                                             int page, int size, String sort) {
        Pageable pageable = createPageable(page, size, sort);
        Page<Product> productPage;

        if (search != null && !search.trim().isEmpty()) {
            productPage = productRepository.searchByKeyword(search.trim(), pageable);
        } else if (subcategory != null && !subcategory.trim().isEmpty()) {
            productPage = productRepository.findBySubcategoryName(subcategory.trim(), pageable);
        } else if (category != null && !category.trim().isEmpty()) {
            productPage = productRepository.findByCategoryGroupName(category.trim(), pageable);
        } else {
            productPage = productRepository.findAllWithCategory(pageable);
        }

        List<ProductDTO> dtos = productPage.getContent().stream()
                .map(this::convertToListDTO)
                .collect(Collectors.toList());

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("products", dtos);
        response.put("currentPage", productPage.getNumber());
        response.put("totalItems", productPage.getTotalElements());
        response.put("totalPages", productPage.getTotalPages());
        response.put("pageSize", productPage.getSize());

        return response;
    }

    /**
     * Get all categories with their subcategories.
     */
    @Cacheable(value = "categories")
    public List<CategoryDTO> getCategories() {
        List<CategoryGroup> groups = categoryGroupRepository.findAllWithSubcategories();

        return groups.stream().map(cg -> {
            CategoryDTO dto = new CategoryDTO();
            dto.setId(cg.getId());
            dto.setName(cg.getName());
            dto.setSubcategories(cg.getSubcategories().stream()
                    .map(sc -> new CategoryDTO.SubcategoryDTO(sc.getId(), sc.getName()))
                    .collect(Collectors.toList()));
            return dto;
        }).collect(Collectors.toList());
    }

    // =========================================================================
    // HELPER METHODS
    // =========================================================================

    private ProductDTO convertToDTO(Product p) {
        ProductDTO dto = new ProductDTO();
        dto.setProductId(p.getProductId());
        dto.setTitle(p.getTitle());
        dto.setProductDescription(p.getProductDescription());
        dto.setRating(p.getRating());
        dto.setRatingsCount(p.getRatingsCount());
        dto.setInitialPrice(p.getInitialPrice());
        dto.setDiscount(p.getDiscount());
        dto.setFinalPrice(computeFinalPrice(p));
        dto.setCurrency(p.getCurrency());
        dto.setDeliveryOptions(p.getDeliveryOptions());
        dto.setProductDetails(p.getProductDetails());
        dto.setSellerName(p.getSellerName());
        dto.setWhatCustomersSaid(p.getWhatCustomersSaid());

        if (p.getSubcategory() != null) {
            dto.setSubcategory(p.getSubcategory().getName());
            if (p.getSubcategory().getCategoryGroup() != null) {
                dto.setCategoryGroup(p.getSubcategory().getCategoryGroup().getName());
            }
        }

        dto.setImages(p.getImages().stream()
                .map(ProductImage::getImageUrl)
                .collect(Collectors.toList()));

        dto.setSizes(p.getSizes().stream()
                .map(s -> new ProductDTO.SizeDTO(s.getSize()))
                .collect(Collectors.toList()));

        dto.setSpecifications(p.getSpecifications().stream()
                .map(s -> new ProductDTO.SpecDTO(s.getSpecName(), s.getSpecValue()))
                .collect(Collectors.toList()));

        dto.setOffers(p.getOffers().stream()
                .map(o -> new ProductDTO.OfferDTO(o.getOfferName(), o.getOfferValue()))
                .collect(Collectors.toList()));

        try {
            if (p.getStarRating() != null) {
                ProductDTO.StarRatingDTO srDto = new ProductDTO.StarRatingDTO();
                srDto.setStar1(p.getStarRating().getStar1() != null ? p.getStarRating().getStar1() : 0);
                srDto.setStar2(p.getStarRating().getStar2() != null ? p.getStarRating().getStar2() : 0);
                srDto.setStar3(p.getStarRating().getStar3() != null ? p.getStarRating().getStar3() : 0);
                srDto.setStar4(p.getStarRating().getStar4() != null ? p.getStarRating().getStar4() : 0);
                srDto.setStar5(p.getStarRating().getStar5() != null ? p.getStarRating().getStar5() : 0);
                dto.setStarRating(srDto);
            }
        } catch (jakarta.persistence.EntityNotFoundException e) {
            // StarRating record not found for this product - skip gracefully
            dto.setStarRating(null);
        }

        return dto;
    }

    private ProductDTO convertToListDTO(Product p) {
        ProductDTO dto = new ProductDTO();
        dto.setProductId(p.getProductId());
        dto.setTitle(p.getTitle());
        dto.setProductDescription(p.getProductDescription());
        dto.setRating(p.getRating());
        dto.setRatingsCount(p.getRatingsCount());
        dto.setInitialPrice(p.getInitialPrice());
        dto.setDiscount(p.getDiscount());
        dto.setFinalPrice(computeFinalPrice(p));
        dto.setCurrency(p.getCurrency());

        if (p.getSubcategory() != null) {
            dto.setSubcategory(p.getSubcategory().getName());
            if (p.getSubcategory().getCategoryGroup() != null) {
                dto.setCategoryGroup(p.getSubcategory().getCategoryGroup().getName());
            }
        }

        // Only first image for list view
        if (p.getImages() != null && !p.getImages().isEmpty()) {
            dto.setImages(List.of(p.getImages().get(0).getImageUrl()));
        } else {
            dto.setImages(List.of());
        }

        if (p.getSizes() != null) {
            dto.setSizes(p.getSizes().stream()
                    .map(s -> new ProductDTO.SizeDTO(s.getSize()))
                    .collect(Collectors.toList()));
        }

        return dto;
    }

    /**
     * Compute the correct finalPrice from initialPrice and discount.
     * The seed data has many products where finalPrice == initialPrice despite having discounts.
     * Formula: finalPrice = initialPrice * (1 - discount/100), formatted as "$X".
     * Falls back to the stored value if initialPrice or discount is unavailable.
     */
    private String computeFinalPrice(Product p) {
        if (p.getInitialPrice() != null && p.getDiscount() != null && p.getDiscount() > 0) {
            long computed = Math.round(p.getInitialPrice() * (1.0 - p.getDiscount() / 100.0));
            return "$" + computed;
        }
        // No discount or missing data — fall back to stored value
        if (p.getFinalPrice() != null) {
            return p.getFinalPrice();
        }
        // Last resort — use initialPrice
        if (p.getInitialPrice() != null) {
            return "$" + p.getInitialPrice();
        }
        return "$0";
    }

    private Pageable createPageable(int page, int size, String sort) {
        Sort sortOrder = Sort.unsorted();
        if (sort != null) {
            switch (sort) {
                case "price_asc":
                    sortOrder = Sort.by("initialPrice").ascending();
                    break;
                case "price_desc":
                    sortOrder = Sort.by("initialPrice").descending();
                    break;
                case "rating":
                    sortOrder = Sort.by("rating").descending();
                    break;
                case "newest":
                    sortOrder = Sort.by("createdAt").descending();
                    break;
                case "discount":
                    sortOrder = Sort.by("discount").descending();
                    break;
            }
        }
        return PageRequest.of(page, size, sortOrder);
    }
}
