package com.github.Bahaaio.monolith.service;

import com.github.Bahaaio.monolith.model.Order;
import com.github.Bahaaio.monolith.model.Product;
import com.github.Bahaaio.monolith.repository.OrderRepository;
import com.github.Bahaaio.shared.dto.OrderRequest;
import com.github.Bahaaio.shared.model.OrderStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;

@Service
public class OrderService {

    private final OrderRepository orderRepository;
    private final UserService userService;
    private final ProductService productService;

    public OrderService(OrderRepository orderRepository, UserService userService, ProductService productService) {
        this.orderRepository = orderRepository;
        this.userService = userService;
        this.productService = productService;
    }

    @Transactional(readOnly = true)
    public List<Order> getAllOrders() {
        return orderRepository.findAll();
    }

    @Transactional(readOnly = true)
    public Order getOrderById(Long id) {
        return orderRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Order not found: " + id));
    }

    @Transactional
    public Order createOrder(OrderRequest request) {
        // Validate user exists
        if (!userService.existsById(request.getUserId())) {
            throw new RuntimeException("User not found: " + request.getUserId());
        }

        // Validate product exists and has sufficient stock
        Product product = productService.getProductById(request.getProductId());
        if (product.getStock() < request.getQuantity()) {
            throw new RuntimeException("Insufficient stock for product: " + product.getId());
        }

        // Calculate total price
        BigDecimal totalPrice = product.getPrice().multiply(BigDecimal.valueOf(request.getQuantity()));

        Order order = new Order(request.getUserId(), request.getProductId(), request.getQuantity(), totalPrice);
        order.setStatus(OrderStatus.CONFIRMED);

        // Decrease stock
        product.setStock(product.getStock() - request.getQuantity());

        return orderRepository.save(order);
    }
}
