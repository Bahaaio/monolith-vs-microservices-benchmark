package com.github.Bahaaio.productservice.repository;

import com.github.Bahaaio.productservice.model.Product;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProductRepository extends JpaRepository<Product, Long> {
}
