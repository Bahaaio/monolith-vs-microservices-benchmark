package com.github.Bahaaio.monolith.service;

import com.github.Bahaaio.monolith.config.ChaosProperties;
import com.github.Bahaaio.monolith.model.Product;
import com.github.Bahaaio.monolith.repository.ProductRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class ProductService {

    private final ProductRepository productRepository;
    private final ChaosProperties chaosProperties;

    public ProductService(ProductRepository productRepository, ChaosProperties chaosProperties) {
        this.productRepository = productRepository;
        this.chaosProperties = chaosProperties;
    }

    @Transactional(readOnly = true)
    public List<Product> getAllProducts() {
        return productRepository.findAll();
    }

    @Transactional(readOnly = true)
    public Product getProductById(Long id) {
        maybeInjectChaos(id);
        return productRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Product not found: " + id));
    }

    @Transactional
    public Product createProduct(Product product) {
        return productRepository.save(product);
    }

    private void maybeInjectChaos(Long id) {
        if (!chaosProperties.isEnabled()) {
            return;
        }

        String mode = chaosProperties.getMode();
        if ("latency".equalsIgnoreCase(mode)) {
            int delayMs = Math.max(0, chaosProperties.getLatencyMs());
            if (delayMs > 0) {
                try {
                    Thread.sleep(delayMs);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("Latency injection interrupted", e);
                }
            }
            return;
        }

        if ("fault".equalsIgnoreCase(mode)) {
            int percent = Math.max(0, Math.min(100, chaosProperties.getFaultPercent()));
            int bucket = Math.floorMod(id.intValue(), 100);
            if (bucket < percent) {
                throw new RuntimeException("Injected deterministic fault in GET /products/{id}");
            }
        }
    }
}
