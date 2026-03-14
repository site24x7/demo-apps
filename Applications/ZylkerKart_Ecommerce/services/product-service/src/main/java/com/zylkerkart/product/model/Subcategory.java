package com.zylkerkart.product.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import java.io.Serializable;

@Entity
@Table(name = "subcategories")
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
public class Subcategory implements Serializable {

    private static final long serialVersionUID = 1L;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    @Column(nullable = false, length = 50)
    private String name;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "category_group_id", nullable = false)
    private CategoryGroup categoryGroup;

    public Subcategory() {}

    public Integer getId() { return id; }
    public void setId(Integer id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public CategoryGroup getCategoryGroup() { return categoryGroup; }
    public void setCategoryGroup(CategoryGroup categoryGroup) { this.categoryGroup = categoryGroup; }
}
