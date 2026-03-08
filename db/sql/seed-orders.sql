-- Seed data: 10 initial orders

INSERT INTO orders (user_id, product_id, quantity, total_price, status) VALUES
(1, 1, 1, 1299.99, 'CONFIRMED'),
(2, 3, 2, 99.98, 'CONFIRMED'),
(3, 7, 1, 199.99, 'SHIPPED'),
(4, 11, 2, 259.98, 'DELIVERED'),
(5, 16, 1, 59.99, 'CONFIRMED'),
(1, 2, 3, 89.97, 'CONFIRMED'),
(6, 21, 1, 79.99, 'PENDING'),
(7, 26, 1, 59.99, 'CONFIRMED'),
(8, 8, 1, 899.99, 'SHIPPED'),
(9, 30, 2, 79.98, 'CONFIRMED');
