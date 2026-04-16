package com.github.Bahaaio.productservice.service;

import com.github.Bahaaio.productservice.config.ChaosProperties;
import com.github.Bahaaio.productservice.model.Product;
import com.github.Bahaaio.productservice.repository.ProductRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class ProductService {

    private final ProductRepository productRepository;
    private final ChaosProperties chaosProperties;
    private volatile Set<Long> faultIdSet = Set.of();
    private volatile String cachedFaultIdsRaw = "";

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
                .orElseThrow(() -> new RuntimeException("Product not found with id: " + id));
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
            Set<Long> faultIds = getFaultIdSet();
            if (faultIds.contains(id)) {
                throw new RuntimeException("Injected deterministic fault in GET /products/{id}");
            }
        }
    }

    private Set<Long> getFaultIdSet() {
        String raw = chaosProperties.getFaultIds();
        if (raw == null) {
            raw = "";
        }

        if (raw.equals(cachedFaultIdsRaw)) {
            return faultIdSet;
        }

        Set<Long> parsed = Arrays.stream(raw.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .map(Long::valueOf)
                .collect(Collectors.toCollection(HashSet::new));

        faultIdSet = Set.copyOf(parsed);
        cachedFaultIdsRaw = raw;
        return faultIdSet;
    }
}
