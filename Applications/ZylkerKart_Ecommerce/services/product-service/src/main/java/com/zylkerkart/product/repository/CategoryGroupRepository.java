package com.zylkerkart.product.repository;

import com.zylkerkart.product.model.CategoryGroup;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface CategoryGroupRepository extends JpaRepository<CategoryGroup, Integer> {

    @Query("SELECT cg FROM CategoryGroup cg LEFT JOIN FETCH cg.subcategories")
    List<CategoryGroup> findAllWithSubcategories();
}
