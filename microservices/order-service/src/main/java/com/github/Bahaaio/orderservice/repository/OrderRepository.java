package com.github.Bahaaio.orderservice.repository;

import com.github.Bahaaio.orderservice.model.Order;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderRepository extends JpaRepository<Order, Long> {
}
