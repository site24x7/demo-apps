package com.zylkerkart.product.repository;

import com.zylkerkart.product.model.Product;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface ProductRepository extends JpaRepository<Product, Long> {

    @EntityGraph(attributePaths = {"subcategory", "subcategory.categoryGroup"})
    Optional<Product> findByProductId(Long productId);

    @Query("SELECT p FROM Product p JOIN FETCH p.subcategory s JOIN FETCH s.categoryGroup")
    Page<Product> findAllWithCategory(Pageable pageable);

    @Query("SELECT p FROM Product p JOIN p.subcategory s JOIN s.categoryGroup cg WHERE cg.name = :groupName")
    Page<Product> findByCategoryGroupName(@Param("groupName") String groupName, Pageable pageable);

    @Query("SELECT p FROM Product p JOIN p.subcategory s WHERE s.name = :subcategory")
    Page<Product> findBySubcategoryName(@Param("subcategory") String subcategory, Pageable pageable);

    @Query("SELECT p FROM Product p WHERE LOWER(p.title) LIKE LOWER(CONCAT('%', :keyword, '%')) " +
           "OR LOWER(p.productDescription) LIKE LOWER(CONCAT('%', :keyword, '%'))")
    Page<Product> searchByKeyword(@Param("keyword") String keyword, Pageable pageable);
}
