package com.github.Bahaaio.monolith.repository;

import com.github.Bahaaio.monolith.model.Product;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface ProductRepository extends JpaRepository<Product, Long> {
}
