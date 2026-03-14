package com.zylkerkart.product.dto;

import java.io.Serializable;
import java.util.List;

public class CategoryDTO implements Serializable {

    private static final long serialVersionUID = 1L;

    private Integer id;
    private String name;
    private List<SubcategoryDTO> subcategories;

    public CategoryDTO() {}

    public Integer getId() { return id; }
    public void setId(Integer id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public List<SubcategoryDTO> getSubcategories() { return subcategories; }
    public void setSubcategories(List<SubcategoryDTO> subcategories) { this.subcategories = subcategories; }

    public static class SubcategoryDTO implements Serializable {
        private Integer id;
        private String name;

        public SubcategoryDTO() {}
        public SubcategoryDTO(Integer id, String name) { this.id = id; this.name = name; }

        public Integer getId() { return id; }
        public void setId(Integer id) { this.id = id; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
    }
}
