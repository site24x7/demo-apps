package com.zylkerkart.product.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import org.hibernate.annotations.NotFound;
import org.hibernate.annotations.NotFoundAction;
import java.io.Serializable;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "products")
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
public class Product implements Serializable {

    private static final long serialVersionUID = 1L;

    @Id
    @Column(name = "product_id")
    private Long productId;

    @Column(nullable = false)
    private String title;

    @Column(name = "product_description", columnDefinition = "TEXT")
    private String productDescription;

    @Column(precision = 2, scale = 1)
    private BigDecimal rating;

    @Column(name = "ratings_count")
    private Integer ratingsCount;

    @Column(name = "initial_price")
    private Integer initialPrice;

    private Integer discount;

    @Column(name = "final_price", length = 20)
    private String finalPrice;

    @Column(length = 3)
    private String currency;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "subcategory_id", nullable = false)
    private Subcategory subcategory;

    @Column(name = "delivery_options", columnDefinition = "JSON")
    private String deliveryOptions;

    @Column(name = "product_details", columnDefinition = "JSON")
    private String productDetails;

    @Column(name = "what_customers_said", columnDefinition = "TEXT")
    private String whatCustomersSaid;

    @Column(name = "seller_name")
    private String sellerName;

    @OneToMany(mappedBy = "product", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @OrderBy("imageOrder ASC")
    private List<ProductImage> images = new ArrayList<>();

    @OneToMany(mappedBy = "product", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private List<ProductSpecification> specifications = new ArrayList<>();

    @OneToMany(mappedBy = "product", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private List<ProductSize> sizes = new ArrayList<>();

    @OneToMany(mappedBy = "product", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private List<ProductOffer> offers = new ArrayList<>();

    @OneToOne(mappedBy = "product", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @NotFound(action = NotFoundAction.IGNORE)
    private StarRating starRating;

    @OneToMany(mappedBy = "product", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @OrderBy("breadcrumbOrder ASC")
    private List<Breadcrumb> breadcrumbs = new ArrayList<>();

    @Column(name = "created_at")
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    // Constructors
    public Product() {}

    // Getters and Setters
    public Long getProductId() { return productId; }
    public void setProductId(Long productId) { this.productId = productId; }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public String getProductDescription() { return productDescription; }
    public void setProductDescription(String productDescription) { this.productDescription = productDescription; }

    public BigDecimal getRating() { return rating; }
    public void setRating(BigDecimal rating) { this.rating = rating; }

    public Integer getRatingsCount() { return ratingsCount; }
    public void setRatingsCount(Integer ratingsCount) { this.ratingsCount = ratingsCount; }

    public Integer getInitialPrice() { return initialPrice; }
    public void setInitialPrice(Integer initialPrice) { this.initialPrice = initialPrice; }

    public Integer getDiscount() { return discount; }
    public void setDiscount(Integer discount) { this.discount = discount; }

    public String getFinalPrice() { return finalPrice; }
    public void setFinalPrice(String finalPrice) { this.finalPrice = finalPrice; }

    public String getCurrency() { return currency; }
    public void setCurrency(String currency) { this.currency = currency; }

    public Subcategory getSubcategory() { return subcategory; }
    public void setSubcategory(Subcategory subcategory) { this.subcategory = subcategory; }

    public String getDeliveryOptions() { return deliveryOptions; }
    public void setDeliveryOptions(String deliveryOptions) { this.deliveryOptions = deliveryOptions; }

    public String getProductDetails() { return productDetails; }
    public void setProductDetails(String productDetails) { this.productDetails = productDetails; }

    public String getWhatCustomersSaid() { return whatCustomersSaid; }
    public void setWhatCustomersSaid(String whatCustomersSaid) { this.whatCustomersSaid = whatCustomersSaid; }

    public String getSellerName() { return sellerName; }
    public void setSellerName(String sellerName) { this.sellerName = sellerName; }

    public List<ProductImage> getImages() { return images; }
    public void setImages(List<ProductImage> images) { this.images = images; }

    public List<ProductSpecification> getSpecifications() { return specifications; }
    public void setSpecifications(List<ProductSpecification> specifications) { this.specifications = specifications; }

    public List<ProductSize> getSizes() { return sizes; }
    public void setSizes(List<ProductSize> sizes) { this.sizes = sizes; }

    public List<ProductOffer> getOffers() { return offers; }
    public void setOffers(List<ProductOffer> offers) { this.offers = offers; }

    public StarRating getStarRating() { return starRating; }
    public void setStarRating(StarRating starRating) { this.starRating = starRating; }

    public List<Breadcrumb> getBreadcrumbs() { return breadcrumbs; }
    public void setBreadcrumbs(List<Breadcrumb> breadcrumbs) { this.breadcrumbs = breadcrumbs; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }
}
