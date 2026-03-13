-- =============================================================================
-- ZylkerKart - Database Schema Initialization
-- Creates 5 databases: db_product, db_order, db_search, db_payment, db_auth
-- =============================================================================

-- =============================================================================
-- DATABASE: db_product (Product Catalog - Used by Java/Spring Boot Service)
-- =============================================================================
CREATE DATABASE IF NOT EXISTS db_product CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_product;

CREATE TABLE IF NOT EXISTS category_groups (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS subcategories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    category_group_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_subcat_group (name, category_group_id),
    FOREIGN KEY (category_group_id) REFERENCES category_groups(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS products (
    product_id BIGINT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    product_description TEXT,
    rating DECIMAL(2,1) DEFAULT NULL,
    ratings_count INT DEFAULT 0,
    initial_price INT DEFAULT NULL,
    discount INT DEFAULT 0,
    final_price VARCHAR(20) DEFAULT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    subcategory_id INT NOT NULL,
    delivery_options JSON DEFAULT NULL,
    product_details JSON DEFAULT NULL,
    what_customers_said TEXT DEFAULT NULL,
    seller_name VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_subcategory (subcategory_id),
    INDEX idx_rating (rating),
    INDEX idx_price (initial_price),
    INDEX idx_title (title),
    FOREIGN KEY (subcategory_id) REFERENCES subcategories(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS product_images (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    image_url TEXT NOT NULL,
    image_order INT NOT NULL DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_product (product_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS product_specifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    spec_name VARCHAR(255) NOT NULL,
    spec_value VARCHAR(500) DEFAULT NULL,
    INDEX idx_product (product_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS product_sizes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    size VARCHAR(50) NOT NULL,
    INDEX idx_product (product_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS product_offers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    offer_name VARCHAR(500) NOT NULL,
    offer_value VARCHAR(500) DEFAULT NULL,
    INDEX idx_product (product_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS star_ratings (
    product_id BIGINT PRIMARY KEY,
    star_1 INT DEFAULT 0,
    star_2 INT DEFAULT 0,
    star_3 INT DEFAULT 0,
    star_4 INT DEFAULT 0,
    star_5 INT DEFAULT 0,
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS breadcrumbs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    breadcrumb_order INT NOT NULL DEFAULT 0,
    name VARCHAR(255) NOT NULL,
    url TEXT DEFAULT NULL,
    INDEX idx_product (product_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =============================================================================
-- DATABASE: db_order (Order Management - Used by Node.js/Express Service)
-- =============================================================================
CREATE DATABASE IF NOT EXISTS db_order CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_order;

CREATE TABLE IF NOT EXISTS customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT DEFAULT NULL,
    session_id VARCHAR(128) DEFAULT NULL,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) DEFAULT NULL,
    phone VARCHAR(20) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_session (session_id),
    INDEX idx_email (email)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    user_id INT DEFAULT NULL,
    total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status ENUM('pending','confirmed','processing','shipped','delivered','cancelled') DEFAULT 'pending',
    shipping_address TEXT DEFAULT NULL,
    notes TEXT DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_customer (customer_id),
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created (created_at),
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    product_id BIGINT NOT NULL,
    product_title VARCHAR(255) NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price DECIMAL(10,2) NOT NULL,
    size VARCHAR(50) DEFAULT NULL,
    image_url TEXT DEFAULT NULL,
    INDEX idx_order (order_id),
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =============================================================================
-- DATABASE: db_search (Search & Autocomplete - Used by Go/Gin Service)
-- =============================================================================
CREATE DATABASE IF NOT EXISTS db_search CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_search;

CREATE TABLE IF NOT EXISTS search_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    query VARCHAR(500) NOT NULL,
    session_id VARCHAR(128) DEFAULT NULL,
    results_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_query (query(100)),
    INDEX idx_session (session_id),
    INDEX idx_created (created_at)
) ENGINE=InnoDB;

-- =============================================================================
-- DATABASE: db_payment (Payment Transactions - Used by Python/FastAPI Service)
-- =============================================================================
CREATE DATABASE IF NOT EXISTS db_payment CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_payment;

CREATE TABLE IF NOT EXISTS transactions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    user_id INT DEFAULT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    method ENUM('credit_card','debit_card','upi','wallet','cod') DEFAULT 'credit_card',
    status ENUM('pending','processing','success','failed','refunded') DEFAULT 'pending',
    transaction_ref VARCHAR(128) DEFAULT NULL,
    fraud_score DECIMAL(3,2) DEFAULT NULL,
    error_message TEXT DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_order (order_id),
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_ref (transaction_ref)
) ENGINE=InnoDB;

-- =============================================================================
-- DATABASE: db_auth (Authentication - Used by C#/.NET Service)
-- =============================================================================
CREATE DATABASE IF NOT EXISTS db_auth CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_auth;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    phone VARCHAR(20) DEFAULT NULL,
    address TEXT DEFAULT NULL,
    is_locked BOOLEAN DEFAULT FALSE,
    failed_attempts INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    token VARCHAR(512) NOT NULL UNIQUE,
    expires_at DATETIME NOT NULL,
    is_revoked BOOLEAN DEFAULT FALSE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user (user_id),
    INDEX idx_token (token),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS user_activity (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    order_id INT DEFAULT NULL,
    transaction_id INT DEFAULT NULL,
    activity_type ENUM('login','logout','register','order_placed','payment_success','payment_failed','password_change') NOT NULL,
    metadata JSON DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user (user_id),
    INDEX idx_activity (activity_type),
    INDEX idx_created (created_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Insert demo user (password: Demo@123 - BCrypt hash)
INSERT IGNORE INTO users (email, password_hash, full_name, phone, address)
VALUES ('demo@zylkerkart.com', '$2b$11$xmFNTWvNtfX30SfJilDV7uKA9JUR5z9mdOsxZoF1oNbxih8SCMdJm', 'Demo User', '+1-555-0100', '123 Demo Street, San Francisco, CA 94102');
