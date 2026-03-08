package com.github.Bahaaio.monolith.model;

import com.github.Bahaaio.shared.model.BaseProduct;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

import java.math.BigDecimal;

@Entity
@Table(name = "products")
public class Product extends BaseProduct {

    public Product() {}

    public Product(String name, String description, BigDecimal price, Integer stock, String category) {
        super(name, description, price, stock, category);
    }
}
