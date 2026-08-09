CREATE TABLE stores (
    store_id VARCHAR(50) PRIMARY KEY,
    store_name VARCHAR(100),
    city VARCHAR(100),
    country VARCHAR(100)
);

CREATE TABLE category (
    category_id VARCHAR(50) PRIMARY KEY,
    category_name VARCHAR(100)
);

CREATE TABLE products (
    product_id VARCHAR(50) PRIMARY KEY,
    product_name VARCHAR(255),
    category_id VARCHAR(50) REFERENCES category(category_id),
    launch_date DATE,
    price NUMERIC
);

CREATE TABLE sales (
    sale_id VARCHAR(50) PRIMARY KEY,
    sale_date DATE,
    store_id VARCHAR(50) REFERENCES stores(store_id),
    product_id VARCHAR(50) REFERENCES products(product_id),
    quantity INT
);

CREATE TABLE warranty (
    claim_id VARCHAR(50) PRIMARY KEY,
    claim_date DATE,
    sale_id VARCHAR(50) REFERENCES sales(sale_id),
    repair_status VARCHAR (100)
);