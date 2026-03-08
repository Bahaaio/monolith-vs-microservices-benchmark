package com.github.Bahaaio.orderservice.service;

import com.github.Bahaaio.orderservice.model.Order;
import com.github.Bahaaio.orderservice.repository.OrderRepository;
import com.github.Bahaaio.shared.dto.OrderRequest;
import com.github.Bahaaio.shared.dto.ProductDto;
import com.github.Bahaaio.shared.dto.UserDto;
import com.github.Bahaaio.shared.model.OrderStatus;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestTemplate;

import java.math.BigDecimal;
import java.util.List;

@Service
public class OrderService {

    private final RestTemplate restTemplate;
    private final OrderRepository orderRepository;

    @Value("${services.user-service.url}")
    private String userServiceUrl;

    @Value("${services.product-service.url}")
    private String productServiceUrl;

    public OrderService(RestTemplate restTemplate, OrderRepository orderRepository) {
        this.restTemplate = restTemplate;
        this.orderRepository = orderRepository;
    }

    @Transactional(readOnly = true)
    public List<Order> getAllOrders() {
        return orderRepository.findAll();
    }

    @Transactional(readOnly = true)
    public Order getOrderById(Long id) {
        return orderRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Order not found with id: " + id));
    }

    @Transactional
    public Order createOrder(OrderRequest request) {
        UserDto user;
        try {
            user = restTemplate.getForObject(
                    userServiceUrl + "/users/" + request.getUserId(),
                    UserDto.class
            );
        } catch (Exception e) {
            throw new RuntimeException("User service unavailable");
        }

        ProductDto product;
        try {
            product = restTemplate.getForObject(
                    productServiceUrl + "/products/" + request.getProductId(),
                    ProductDto.class
            );
        } catch (Exception e) {
            throw new RuntimeException("Product service unavailable");
        }

        if (product == null || product.getStock() < request.getQuantity()) {
            throw new RuntimeException("Insufficient stock for product: " + request.getProductId());
        }

        BigDecimal totalPrice = product.getPrice().multiply(BigDecimal.valueOf(request.getQuantity()));

        Order order = new Order(request.getUserId(), request.getProductId(), request.getQuantity(), totalPrice);
        order.setStatus(OrderStatus.CONFIRMED);

        return orderRepository.save(order);
    }
}
