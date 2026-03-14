package com.zylkerkart.product.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import java.io.Serializable;

@Entity
@Table(name = "star_ratings")
public class StarRating implements Serializable {

    private static final long serialVersionUID = 1L;

    @Id
    @Column(name = "product_id")
    private Long productId;

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "product_id", insertable = false, updatable = false)
    @JsonIgnore
    private Product product;

    @Column(name = "star_1")
    private Integer star1;

    @Column(name = "star_2")
    private Integer star2;

    @Column(name = "star_3")
    private Integer star3;

    @Column(name = "star_4")
    private Integer star4;

    @Column(name = "star_5")
    private Integer star5;

    public StarRating() {}

    public Long getProductId() { return productId; }
    public void setProductId(Long productId) { this.productId = productId; }
    public Product getProduct() { return product; }
    public void setProduct(Product product) { this.product = product; }
    public Integer getStar1() { return star1; }
    public void setStar1(Integer star1) { this.star1 = star1; }
    public Integer getStar2() { return star2; }
    public void setStar2(Integer star2) { this.star2 = star2; }
    public Integer getStar3() { return star3; }
    public void setStar3(Integer star3) { this.star3 = star3; }
    public Integer getStar4() { return star4; }
    public void setStar4(Integer star4) { this.star4 = star4; }
    public Integer getStar5() { return star5; }
    public void setStar5(Integer star5) { this.star5 = star5; }
}
