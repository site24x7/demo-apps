package com.zylkerkart.product.dto;

import java.io.Serializable;
import java.math.BigDecimal;
import java.util.List;

public class ProductDTO implements Serializable {

    private static final long serialVersionUID = 1L;

    private Long productId;
    private String title;
    private String productDescription;
    private BigDecimal rating;
    private Integer ratingsCount;
    private Integer initialPrice;
    private Integer discount;
    private String finalPrice;
    private String currency;
    private String categoryGroup;
    private String subcategory;
    private List<String> images;
    private List<SizeDTO> sizes;
    private List<SpecDTO> specifications;
    private List<OfferDTO> offers;
    private StarRatingDTO starRating;
    private String deliveryOptions;
    private String productDetails;
    private String sellerName;
    private String whatCustomersSaid;

    // Constructors
    public ProductDTO() {}

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
    public String getCategoryGroup() { return categoryGroup; }
    public void setCategoryGroup(String categoryGroup) { this.categoryGroup = categoryGroup; }
    public String getSubcategory() { return subcategory; }
    public void setSubcategory(String subcategory) { this.subcategory = subcategory; }
    public List<String> getImages() { return images; }
    public void setImages(List<String> images) { this.images = images; }
    public List<SizeDTO> getSizes() { return sizes; }
    public void setSizes(List<SizeDTO> sizes) { this.sizes = sizes; }
    public List<SpecDTO> getSpecifications() { return specifications; }
    public void setSpecifications(List<SpecDTO> specifications) { this.specifications = specifications; }
    public List<OfferDTO> getOffers() { return offers; }
    public void setOffers(List<OfferDTO> offers) { this.offers = offers; }
    public StarRatingDTO getStarRating() { return starRating; }
    public void setStarRating(StarRatingDTO starRating) { this.starRating = starRating; }
    public String getDeliveryOptions() { return deliveryOptions; }
    public void setDeliveryOptions(String deliveryOptions) { this.deliveryOptions = deliveryOptions; }
    public String getProductDetails() { return productDetails; }
    public void setProductDetails(String productDetails) { this.productDetails = productDetails; }
    public String getSellerName() { return sellerName; }
    public void setSellerName(String sellerName) { this.sellerName = sellerName; }
    public String getWhatCustomersSaid() { return whatCustomersSaid; }
    public void setWhatCustomersSaid(String whatCustomersSaid) { this.whatCustomersSaid = whatCustomersSaid; }

    // Inner DTOs
    public static class SizeDTO implements Serializable {
        private String size;
        public SizeDTO() {}
        public SizeDTO(String size) { this.size = size; }
        public String getSize() { return size; }
        public void setSize(String size) { this.size = size; }
    }

    public static class SpecDTO implements Serializable {
        private String name;
        private String value;
        public SpecDTO() {}
        public SpecDTO(String name, String value) { this.name = name; this.value = value; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getValue() { return value; }
        public void setValue(String value) { this.value = value; }
    }

    public static class OfferDTO implements Serializable {
        private String name;
        private String value;
        public OfferDTO() {}
        public OfferDTO(String name, String value) { this.name = name; this.value = value; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getValue() { return value; }
        public void setValue(String value) { this.value = value; }
    }

    public static class StarRatingDTO implements Serializable {
        private int star1;
        private int star2;
        private int star3;
        private int star4;
        private int star5;
        public StarRatingDTO() {}
        public int getStar1() { return star1; }
        public void setStar1(int star1) { this.star1 = star1; }
        public int getStar2() { return star2; }
        public void setStar2(int star2) { this.star2 = star2; }
        public int getStar3() { return star3; }
        public void setStar3(int star3) { this.star3 = star3; }
        public int getStar4() { return star4; }
        public void setStar4(int star4) { this.star4 = star4; }
        public int getStar5() { return star5; }
        public void setStar5(int star5) { this.star5 = star5; }
    }
}
