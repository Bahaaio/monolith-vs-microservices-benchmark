package com.github.Bahaaio.orderservice.model;

import com.github.Bahaaio.shared.model.BaseOrder;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

import java.math.BigDecimal;

@Entity
@Table(name = "orders")
public class Order extends BaseOrder {

    public Order() {}

    public Order(Long userId, Long productId, Integer quantity, BigDecimal totalPrice) {
        super(userId, productId, quantity, totalPrice);
    }
}
