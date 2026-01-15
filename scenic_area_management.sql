-- =============================================
-- 景区管理系统 - 完整数据库初始化脚本
-- 执行顺序：建库 → 建表 → 加字段 → 加约束/触发器 → 插入初始数据 → 存储过程
-- =============================================

-- 1. 删除并重建数据库
DROP DATABASE IF EXISTS db_finalhw;
CREATE DATABASE db_finalhw CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_finalhw;

-- 2. 创建基础表（按依赖顺序）
-- 2.1 会员等级折扣表
CREATE TABLE Member_Level_Discount(
   member_level INT PRIMARY KEY,
   discount_rate DECIMAL(3,2) NOT NULL DEFAULT 1.00,
   remarks VARCHAR(50)
);

-- 2.2 游客表（先创建基础结构，后续加password字段）
CREATE TABLE Tourist(
    tourist_id INT PRIMARY KEY,
    name VARCHAR(10),
    phone VARCHAR(15),
    birthday DATE,
    member_level INT NOT NULL,
    total_spending DECIMAL(12,2) DEFAULT 0.00,
    remarks VARCHAR(50),
    password_hash CHAR(64),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (member_level) REFERENCES Member_Level_Discount(member_level)
);

-- 2.3 产品表
CREATE TABLE Product(
   product_id INT PRIMARY KEY,
   product_name VARCHAR(10) NOT NULL,
   product_type VARCHAR(10) NOT NULL,
   unit_price DECIMAL(10,3) NOT NULL DEFAULT 0.000,
   default_discount DECIMAL(3,2) NOT NULL DEFAULT 1.00,
   remarks VARCHAR(50),
   remaining_stock INT DEFAULT 999 -- 直接在创建表时加库存字段，避免后续ALTER
);

-- 2.4 景点表（新增total_tickets字段，匹配前端）
CREATE TABLE Attraction (
    attraction_id INT PRIMARY KEY AUTO_INCREMENT,
    attraction_name VARCHAR(50),
    status VARCHAR(20) DEFAULT '正常',
    total_tickets INT DEFAULT 0, -- 总放票数
    remaining_tickets INT DEFAULT 0, -- 剩余票数
    remarks VARCHAR(255)
);

-- 2.5 商铺表（直接加入account/password字段，避免后续ALTER）
CREATE TABLE Shop(
	shop_id INT PRIMARY KEY,
	shop_type CHAR(16),
	site_id INT,
	shop_name VARCHAR(256),
	operator VARCHAR(16),
	rent DECIMAL(10, 2),
	comment VARCHAR(256),
	account VARCHAR(50) UNIQUE, -- 账号
	password VARCHAR(100) DEFAULT '123456', -- 密码
	FOREIGN KEY (site_id) REFERENCES Attraction(attraction_id),
	CONSTRAINT rent_constraint CHECK (rent >= 0)
);

-- 2.6 商铺-产品关联表
CREATE TABLE ShopProduct(
	shop_id INT,
	product_id INT,
	comment VARCHAR(256),
	PRIMARY KEY (shop_id, product_id),
	FOREIGN KEY (shop_id) REFERENCES Shop(shop_id),
	FOREIGN KEY (product_id) REFERENCES Product(product_id)
);

-- 2.7 商铺营收表
CREATE TABLE ShopRevenue(
	shop_id INT,
	report_month DATE,
	revenue DECIMAL(10, 2),
	comment VARCHAR(256),
	PRIMARY KEY (shop_id, report_month),
	FOREIGN KEY (shop_id) REFERENCES Shop(shop_id),
	CONSTRAINT report_month_constraint CHECK (EXTRACT(DAY FROM report_month) = 1)
);

-- 2.8 订单表（表名用Orders，避免MySQL关键字）
CREATE TABLE Orders(
	order_id INT PRIMARY KEY,
	tourist_id INT,
	total_price DECIMAL(10, 2) DEFAULT 0.00,
	order_time DATETIME DEFAULT CURRENT_TIMESTAMP,
	order_status CHAR(8) DEFAULT '未支付',
	comment VARCHAR(256),
	FOREIGN KEY (tourist_id) REFERENCES Tourist(tourist_id)
);

-- 2.9 优惠券类型表
CREATE TABLE coupon (
    coupon_type CHAR(8) PRIMARY KEY,
    ceiling_amount DECIMAL(10, 2),
    comment VARCHAR(256),
    CONSTRAINT check_ceiling_amount CHECK (ceiling_amount > 0)
);

-- 2.10 订单明细表
CREATE TABLE OrderInfo(
	order_id INT,
	product_id INT,
	quantity DECIMAL(10, 3) DEFAULT 1.000,
	unit_price DECIMAL(10, 2) DEFAULT 0.00,
	discount DECIMAL(3, 2) DEFAULT 1.00,
	coupon_type CHAR(8),
	comment VARCHAR(256),
	PRIMARY KEY (order_id, product_id),
	FOREIGN KEY (order_id) REFERENCES Orders(order_id),
	FOREIGN KEY (product_id) REFERENCES Product(product_id),
	FOREIGN KEY (coupon_type) REFERENCES Coupon(coupon_type)
);

-- 2.11 游客优惠券表（直接用current_value字段，避免后续修改）
CREATE TABLE TouristCoupon(
	tourist_id INT,
	coupon_type CHAR(8),
	current_value DECIMAL(10, 2) DEFAULT 0.00,
	PRIMARY KEY (tourist_id, coupon_type),
	FOREIGN KEY (tourist_id) REFERENCES Tourist(tourist_id),
	FOREIGN KEY (coupon_type) REFERENCES Coupon(coupon_type),
	CONSTRAINT check_current_value CHECK (current_value >= 0)
);

-- 2.12 景点门票关联表
CREATE TABLE Attraction_Ticket (
    ticket_id INT PRIMARY KEY AUTO_INCREMENT,
    attraction_id INT,
    product_id INT,
    ticket_type VARCHAR(20),
    remarks VARCHAR(255),
    FOREIGN KEY (attraction_id) REFERENCES Attraction(attraction_id),
    FOREIGN KEY (product_id) REFERENCES Product(product_id)
);

-- 2.13 总营收表（提前创建，避免存储过程报错）
CREATE TABLE Total_Revenue(
    report_month DATE PRIMARY KEY,
    total_amount DECIMAL(10,2) DEFAULT 0.00,
    comment VARCHAR(256)
);

-- 3. 补充字段（仅Tourist表需要加password，其他表已直接创建）
ALTER TABLE Tourist ADD COLUMN password VARCHAR(100) DEFAULT '123456';

-- 4. 创建触发器（数据校验）
DELIMITER //

-- 4.1 会员折扣率校验（0-1之间）
CREATE TRIGGER check_discount_rate_insert
BEFORE INSERT ON Member_Level_Discount
FOR EACH ROW
BEGIN
    IF NEW.discount_rate < 0 OR NEW.discount_rate > 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '会员折扣率必须在0-1之间！';
    END IF;
END //

CREATE TRIGGER check_discount_rate_update
BEFORE UPDATE ON Member_Level_Discount
FOR EACH ROW
BEGIN
    IF NEW.discount_rate < 0 OR NEW.discount_rate > 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '会员折扣率必须在0-1之间！';
    END IF;
END //

-- 4.2 产品默认折扣校验（0-1之间）
CREATE TRIGGER trg_check_default_discount_insert
BEFORE INSERT ON Product
FOR EACH ROW
BEGIN
    IF NEW.default_discount < 0 OR NEW.default_discount > 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '产品默认折扣率必须在0-1之间！';
    END IF;
END //

CREATE TRIGGER trg_check_default_discount_update
BEFORE UPDATE ON Product
FOR EACH ROW
BEGIN
    IF NEW.default_discount < 0 OR NEW.default_discount > 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '产品默认折扣率必须在0-1之间！';
    END IF;
END //

-- 4.3 游客累计消费校验（非负）
CREATE TRIGGER check_total_spending_insert
BEFORE INSERT ON Tourist
FOR EACH ROW
BEGIN
    IF NEW.total_spending < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '游客累计消费金额不能为负！';
    END IF;
END //

CREATE TRIGGER check_total_spending_update
BEFORE UPDATE ON Tourist
FOR EACH ROW
BEGIN
    IF NEW.total_spending < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '游客累计消费金额不能为负！';
    END IF;
END //

-- 4.4 优惠券使用校验触发器
CREATE TRIGGER use_coupon BEFORE INSERT ON OrderInfo FOR EACH ROW 
BEGIN
	DECLARE L_tourist_id INT;
	DECLARE L_coupon_amount DECIMAL(10,2);
	
	SELECT O.tourist_id INTO L_tourist_id FROM Orders O WHERE O.order_id = NEW.order_id;
	
	SELECT IFNULL(current_value, 0) INTO L_coupon_amount 
	FROM TouristCoupon TC 
	WHERE TC.tourist_id = L_tourist_id AND TC.coupon_type = NEW.coupon_type;
	
	IF L_coupon_amount = 0 THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '使用的优惠券不合法！';
	ELSE
		UPDATE TouristCoupon TC 
		SET TC.current_value = TC.current_value - 1 
		WHERE TC.tourist_id = L_tourist_id AND TC.coupon_type = NEW.coupon_type;
	END IF;
END //

-- 4.5 优惠券类型校验触发器（冗余校验，增强安全性）
CREATE TRIGGER check_coupon_type_insert BEFORE INSERT ON OrderInfo
FOR EACH ROW
BEGIN
    IF NEW.coupon_type IS NOT NULL AND NEW.coupon_type NOT IN (SELECT coupon_type FROM Coupon) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'coupon_type 不存在于 Coupon 表中，非法值';
    END IF;
END //

CREATE TRIGGER check_coupon_type_update BEFORE UPDATE ON OrderInfo
FOR EACH ROW
BEGIN
    IF NEW.coupon_type IS NOT NULL AND NEW.coupon_type NOT IN (SELECT coupon_type FROM Coupon) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'coupon_type 不存在于 Coupon 表中，非法值';
    END IF;
END //

DELIMITER ;

-- 5. 插入初始数据（所有字段都已存在，不会报错）
-- 5.1 会员等级
INSERT IGNORE INTO Member_Level_Discount (member_level, discount_rate, remarks) VALUES 
(0, 1.00, '普通游客'),
(1, 0.90, 'VIP会员');

-- 5.2 游客（ID:1，密码:123456）
INSERT IGNORE INTO Tourist (tourist_id, name, phone, member_level, password, total_spending) 
VALUES (1, '测试游客', '13800000001', 0, '123456', 0.00);

-- 5.3 景点
INSERT IGNORE INTO Attraction (attraction_id, attraction_name, total_tickets, remaining_tickets) 
VALUES (1, '欢乐谷', 1000, 800);

-- 5.4 商铺（ID:201，账号:kfc，密码:666666）
INSERT IGNORE INTO Shop (shop_id, shop_type, site_id, shop_name, account, password, operator, rent) 
VALUES (201, '餐饮', 1, '肯德基', 'kfc', '666666', '张三', 5000);

-- 5.5 商品
INSERT IGNORE INTO Product (product_id, product_name, product_type, unit_price, remaining_stock) 
VALUES (101, '汉堡包', '餐饮', 30.000, 100);

-- 5.6 优惠券类型
INSERT IGNORE INTO coupon (coupon_type, ceiling_amount, comment) 
VALUES ('LUCKY', 100.00, '拼手气红包最高100元');

-- 6. 创建存储过程
DELIMITER //

-- 6.1 发放随机优惠券
CREATE PROCEDURE sp_grant_random_coupon(
    IN p_tourist_id INT,
    IN p_coupon_type CHAR(8)
)
BEGIN
    DECLARE v_max_amount DECIMAL(10, 2);
    DECLARE v_random_amount DECIMAL(10, 2);
    DECLARE v_count INT;

    SELECT ceiling_amount INTO v_max_amount 
    FROM coupon WHERE coupon_type = p_coupon_type;

    IF v_max_amount IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '错误：该优惠券类型不存在！';
    END IF;

    SET v_random_amount = ROUND((RAND() * (v_max_amount - 0.01)) + 0.01, 2);

    SELECT COUNT(*) INTO v_count 
    FROM touristcoupon 
    WHERE tourist_id = p_tourist_id AND coupon_type = p_coupon_type;

    IF v_count > 0 THEN
        UPDATE touristcoupon 
        SET current_value = current_value + v_random_amount
        WHERE tourist_id = p_tourist_id AND coupon_type = p_coupon_type;
        
        SELECT CONCAT('恭喜！追加获得随机红包 ¥', v_random_amount) AS result;
    ELSE
        INSERT INTO touristcoupon (tourist_id, coupon_type, current_value)
        VALUES (p_tourist_id, p_coupon_type, v_random_amount);
        
        SELECT CONCAT('恭喜！首次获得随机红包 ¥', v_random_amount) AS result;
    END IF;
END //

-- 6.2 计算订单总金额
CREATE PROCEDURE CalcTotalPriceForOrder(IN p_order_id INT)
BEGIN
    DECLARE L_total_price DECIMAL(10, 2) DEFAULT 0;
    DECLARE L_cursor_done SMALLINT DEFAULT 0;
    DECLARE L_cur_unit_price DECIMAL(10, 2);
    DECLARE L_cur_quantity DECIMAL(10, 3);
    DECLARE L_cur_discount DECIMAL(3, 2);
    DECLARE L_cur_coupon_type CHAR(8);
    DECLARE L_cur_coupon_amount DECIMAL(10, 2) DEFAULT 0;
    DECLARE L_tourist_id INT;
    DECLARE L_member_level INT;
    DECLARE L_member_discount DECIMAL(3, 2);

    DECLARE cursor_orderitem CURSOR FOR
        SELECT unit_price, quantity, discount, coupon_type
        FROM OrderInfo WHERE order_id = p_order_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET L_cursor_done = 1;

    IF p_order_id NOT IN (SELECT order_id FROM Orders) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '订单不存在！';
    ELSE
        OPEN cursor_orderitem;
        read_loop: LOOP
            FETCH cursor_orderitem INTO 
                L_cur_unit_price, L_cur_quantity, L_cur_discount, L_cur_coupon_type;
            
            IF L_cursor_done THEN
                LEAVE read_loop;
            END IF;
            
            SET L_cur_coupon_amount = 0;
            
            IF L_cur_coupon_type IS NOT NULL THEN
                SELECT IFNULL(ceiling_amount, 0) INTO L_cur_coupon_amount
                FROM Coupon WHERE coupon_type = L_cur_coupon_type;
            END IF;
            
            SET L_total_price = L_total_price + GREATEST(L_cur_unit_price * L_cur_quantity * L_cur_discount - L_cur_coupon_amount, 0);
        END LOOP;
        CLOSE cursor_orderitem;

        SELECT tourist_id INTO L_tourist_id FROM Orders WHERE order_id = p_order_id;
        
        SELECT IFNULL(member_level, 0) INTO L_member_level
        FROM Tourist WHERE tourist_id = L_tourist_id;
        
        SELECT IFNULL(discount_rate, 1.0) INTO L_member_discount
        FROM Member_Level_Discount WHERE member_level = L_member_level;
        
        UPDATE Orders SET total_price = L_total_price * L_member_discount
        WHERE order_id = p_order_id;
    END IF;
END //

-- 6.3 统计月度总营收
CREATE PROCEDURE CalcTotalRevenue(IN p_month DATE)
BEGIN
    INSERT IGNORE INTO Total_Revenue(report_month, total_amount, comment) 
    VALUES (
        DATE_FORMAT(p_month, "%Y-%m-01"),
        IFNULL((SELECT SUM(total_price) FROM Orders
                WHERE YEAR(order_time) = YEAR(p_month)
                AND MONTH(order_time) = MONTH(p_month)), 0) +
        IFNULL((SELECT SUM(revenue) FROM ShopRevenue 
                WHERE YEAR(report_month) = YEAR(p_month)
                AND MONTH(report_month) = MONTH(p_month)), 0),
        ""
    );
END //

-- 6.4 创建游客角色及数据
CREATE PROCEDURE sp_create_tourist_role_and_data(
    IN p_role_name VARCHAR(50),
    IN p_role_password VARCHAR(100),
    IN p_tourist_id INT,
    IN p_name VARCHAR(10),
    IN p_phone VARCHAR(15),
    IN p_birthday DATE,
    IN p_total_spending DECIMAL(12,5),
    IN p_remarks VARCHAR(50)
)
BEGIN
    SET @create_user_sql = CONCAT('CREATE USER IF NOT EXISTS ''', p_role_name, '''@''%'' IDENTIFIED BY ''', p_role_password, '''');
    PREPARE stmt FROM @create_user_sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    INSERT IGNORE INTO member_level_discount (member_level, discount_rate, remarks) VALUES (0, 1.00, '默认普通游客');
    
    INSERT IGNORE INTO tourist (tourist_id, name, phone, birthday, member_level, total_spending, remarks, password) 
    VALUES (p_tourist_id, p_name, p_phone, p_birthday, 0, IFNULL(p_total_spending, 0), IFNULL(p_remarks, ''), p_role_password);

    SET @view_name = CONCAT('v_tourist_', p_tourist_id);
    SET @sql = CONCAT('CREATE OR REPLACE VIEW ', @view_name, ' AS SELECT tourist_id, name, phone, birthday, member_level, total_spending FROM tourist WHERE tourist_id = ', p_tourist_id, ' WITH CHECK OPTION');
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @view_name_order = CONCAT('v_tourist_order_', p_tourist_id);
    SET @sql = CONCAT('CREATE OR REPLACE VIEW ', @view_name_order, ' AS SELECT order_id, tourist_id, total_price, order_time, order_status, comment FROM Orders WHERE tourist_id = ', p_tourist_id, ' WITH CHECK OPTION');
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @view_name_info = CONCAT('v_tourist_orderinfo_', p_tourist_id);
    SET @sql = CONCAT('CREATE OR REPLACE VIEW ', @view_name_info, ' AS SELECT oi.* FROM OrderInfo oi JOIN Orders o ON oi.order_id = o.order_id WHERE o.tourist_id = ', p_tourist_id);
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @view_name_coupon = CONCAT('v_tourist_coupon_', p_tourist_id);
    SET @sql = CONCAT('CREATE OR REPLACE VIEW ', @view_name_coupon, ' AS SELECT tc.*, c.ceiling_amount FROM touristcoupon tc LEFT JOIN coupon c ON tc.coupon_type = c.coupon_type WHERE tc.tourist_id = ', p_tourist_id);
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @sql = CONCAT('GRANT SELECT ON db_finalhw.', @view_name, ' TO ''', p_role_name, '''@''%''');
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @sql = CONCAT('GRANT SELECT ON db_finalhw.', @view_name_order, ' TO ''', p_role_name, '''@''%''');
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @sql = CONCAT('GRANT SELECT ON db_finalhw.', @view_name_info, ' TO ''', p_role_name, '''@''%''');
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @sql = CONCAT('GRANT SELECT ON db_finalhw.', @view_name_coupon, ' TO ''', p_role_name, '''@''%''');
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @sql = CONCAT('GRANT SELECT ON db_finalhw.product TO ''', p_role_name, '''@''%''');
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @sql = CONCAT('GRANT EXECUTE ON PROCEDURE db_finalhw.CalcTotalPriceForOrder TO ''', p_role_name, '''@''%''');
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    SET @sql = CONCAT('GRANT UPDATE (name, phone, birthday) ON db_finalhw.', @view_name , ' TO ''', p_role_name, '''@''%''');
    PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

    FLUSH PRIVILEGES;
    
    SELECT CONCAT('用户 ', p_role_name, ' 创建成功，ID: ', p_tourist_id) as result;
END //

-- 6.5 创建商铺运营者角色及数据
CREATE PROCEDURE sp_create_shop_operator_role_and_data(
    IN p_role_name VARCHAR(50),
    IN p_role_password VARCHAR(100),
    IN p_shop_id INT
)
BEGIN
    SET @create_role_sql = CONCAT('CREATE ROLE IF NOT EXISTS ''', p_role_name, '''@''%''');
    PREPARE create_role_stmt FROM @create_role_sql;
    EXECUTE create_role_stmt;
    DEALLOCATE PREPARE create_role_stmt;

    SET @set_role_pwd_sql = CONCAT(
        'ALTER USER ''', p_role_name, '''@''%'' IDENTIFIED BY ''', p_role_password, ''''
    );
    PREPARE set_role_pwd_stmt FROM @set_role_pwd_sql;
    EXECUTE set_role_pwd_stmt;
    DEALLOCATE PREPARE set_role_pwd_stmt;

    SET @shop_view_name = CONCAT('v_shop_info_', p_shop_id);
    SET @create_shop_view_sql = CONCAT(
        'CREATE OR REPLACE VIEW ', @shop_view_name, ' AS ',
        'SELECT shop_id, shop_type, site_id, shop_name, operator, rent, comment ',
        'FROM Shop WHERE shop_id = ', p_shop_id, ' ',
        'WITH CHECK OPTION'
    );
    PREPARE create_shop_view_stmt FROM @create_shop_view_sql;
    EXECUTE create_shop_view_stmt;
    DEALLOCATE PREPARE create_shop_view_stmt;

    SET @revenue_view_name = CONCAT('v_shop_revenue_', p_shop_id);
    SET @create_revenue_view_sql = CONCAT(
        'CREATE OR REPLACE VIEW ', @revenue_view_name, ' AS ',
        'SELECT shop_id, report_month, revenue, comment ',
        'FROM ShopRevenue WHERE shop_id = ', p_shop_id, ' ',
        'WITH CHECK OPTION'
    );
    PREPARE create_revenue_view_stmt FROM @create_revenue_view_sql;
    EXECUTE create_revenue_view_stmt;
    DEALLOCATE PREPARE create_revenue_view_stmt;

    SET @grant_shop_view_sql = CONCAT(
        'GRANT SELECT ON db_finalhw.', @shop_view_name, ' TO ''', p_role_name, '''@''%'''
    );
    PREPARE grant_shop_view_stmt FROM @grant_shop_view_sql;
    EXECUTE grant_shop_view_stmt;
    DEALLOCATE PREPARE grant_shop_view_stmt;

    SET @grant_shop_update_sql = CONCAT(
        'GRANT UPDATE (shop_type, site_id, shop_name, comment) ON db_finalhw.Shop TO ''', p_role_name, '''@''%'''
    );
    PREPARE grant_shop_update_stmt FROM @grant_shop_update_sql;
    EXECUTE grant_shop_update_stmt;
    DEALLOCATE PREPARE grant_shop_update_stmt;

    SET @grant_revenue_view_sql = CONCAT(
        'GRANT SELECT ON db_finalhw.', @revenue_view_name, ' TO ''', p_role_name, '''@''%'''
    );
    PREPARE grant_revenue_view_stmt FROM @grant_revenue_view_sql;
    EXECUTE grant_revenue_view_stmt;
    DEALLOCATE PREPARE grant_revenue_view_stmt;

    SET @grant_revenue_update_sql = CONCAT(
        'GRANT UPDATE (report_month, revenue) ON db_finalhw.ShopRevenue TO ''', p_role_name, '''@''%'''
    );
    PREPARE grant_revenue_update_stmt FROM @grant_revenue_update_sql;
    EXECUTE grant_revenue_update_stmt;
    DEALLOCATE PREPARE grant_revenue_update_stmt;

    SET @grant_revenue_insert_sql = CONCAT(
        'GRANT INSERT (shop_id, report_month, revenue, comment) ON db_finalhw.ShopRevenue TO ''', p_role_name, '''@''%'''
    );
    PREPARE grant_revenue_insert_stmt FROM @grant_revenue_insert_sql;
    EXECUTE grant_revenue_insert_stmt;
    DEALLOCATE PREPARE grant_revenue_insert_stmt;

    SET @revoke_shop_sql = CONCAT(
        'REVOKE SELECT, INSERT, DELETE, ALTER ON db_finalhw.Shop FROM ''', p_role_name, '''@''%'''
    );
    PREPARE revoke_shop_stmt FROM @revoke_shop_sql;
    EXECUTE revoke_shop_stmt;
    DEALLOCATE PREPARE revoke_shop_stmt;

    SET @revoke_revenue_sql = CONCAT(
        'REVOKE SELECT, DELETE, ALTER ON db_finalhw.ShopRevenue FROM ''', p_role_name, '''@''%'''
    );
    PREPARE revoke_revenue_stmt FROM @revoke_revenue_sql;
    EXECUTE revoke_revenue_stmt;
    DEALLOCATE PREPARE revoke_revenue_stmt;

    FLUSH PRIVILEGES;

    SELECT CONCAT(
        '商铺运营者角色【', p_role_name, '】创建成功，商铺ID【', p_shop_id, '】'
    ) AS result;
END //

DELIMITER ;

-- 7. 创建索引（优化查询）
CREATE INDEX index_tourist_id ON Tourist(tourist_id);
CREATE INDEX index_product_id ON Product(product_id);
CREATE INDEX index_shop_id ON Shop(shop_id);
CREATE INDEX index_order_id ON Orders(order_id);

-- 8. 创建视图
CREATE OR REPLACE VIEW v_shop_info AS SELECT * FROM Shop;
CREATE OR REPLACE VIEW PRODUCT_TOURIST AS 
SELECT p.product_name, p.product_type, p.unit_price, p.default_discount, p.remarks 
FROM Product p WITH CHECK OPTION;
CREATE OR REPLACE VIEW MERCHANT_TOURIST AS 
SELECT s.shop_type, s.site_id, s.shop_name FROM Shop s WITH CHECK OPTION;
CREATE OR REPLACE VIEW v_ticket_list AS
SELECT
    a.attraction_name AS `景点名称`,
    at.ticket_type AS `门票类型`,
    p.unit_price AS `单价`,
    p.default_discount AS `当前折扣`,
    a.remaining_tickets AS `剩余票数`,
    at.remarks AS `备注`
FROM Attraction_Ticket at
JOIN Attraction a ON at.attraction_id = a.attraction_id
JOIN Product p ON at.product_id = p.product_id;

DELIMITER $$
DROP PROCEDURE IF EXISTS BuyTicket$$
CREATE PROCEDURE BuyTicket(
	IN p_tourist_id INT, 
	IN p_ticket_id INT, 
	IN p_quantity INT, 
	IN p_coupon_type CHAR(8)
)
BEGIN
	-- 声明变量（修正MySQL语法，移除表变量）
	DECLARE L_site_id INT;
	DECLARE L_order_id INT;
	DECLARE L_product_id INT;
	DECLARE L_unit_price DECIMAL(10,3);
	DECLARE L_default_discount DECIMAL(3,2);
	DECLARE L_remaining_tickets INT;
	DECLARE L_coupon_count INT DEFAULT 0;
	
	-- ========== 1. 校验输入参数 ==========
	-- 校验游客是否存在
	IF NOT EXISTS (SELECT 1 FROM Tourist T WHERE T.tourist_id = p_tourist_id) THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '错误：用户不存在！';
	END IF;
	
	-- 校验门票是否存在（修正字段名：p_ticket_id → ticket_id）
	IF NOT EXISTS (SELECT 1 FROM Attraction_Ticket AtT WHERE AtT.ticket_id = p_ticket_id) THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '错误：门票不存在！';
	END IF;
	
	-- 校验票数合法性
	IF p_quantity <= 0 THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '错误：票数不合法（必须大于0）！';
	END IF;
	
	-- ========== 2. 校验优惠券（如果传入） ==========
	IF p_coupon_type IS NOT NULL THEN
		-- 校验优惠券是否属于当前用户（修正变量：tourist_id → p_tourist_id）
		IF NOT EXISTS (
			SELECT 1 FROM TouristCoupon TC 
			WHERE TC.tourist_id = p_tourist_id AND TC.coupon_type = p_coupon_type
		) THEN
			SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '错误：用户没有指定的优惠券！';
		END IF;
		
		-- 校验优惠券数量是否足够（修正字段：quantity → current_value）
		SELECT IFNULL(TC.coupon_type, 0) INTO L_coupon_count
		FROM TouristCoupon TC 
		WHERE TC.tourist_id = p_tourist_id AND TC.coupon_type = p_coupon_type;
		
		IF L_coupon_count < p_quantity THEN
			SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '错误：用户的优惠券数量不足！';
		END IF;
	END IF;
	
	-- ========== 3. 校验景点剩余票数 ==========
	-- 获取门票关联的景点ID
	SELECT AtT.attraction_id INTO L_site_id
	FROM Attraction_Ticket AtT WHERE AtT.ticket_id = p_ticket_id;
	
	-- 获取景点剩余票数
	SELECT A.remaining_tickets INTO L_remaining_tickets
	FROM Attraction A WHERE A.attraction_id = L_site_id;
	
	IF L_remaining_tickets < p_quantity THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '错误：景点剩余票数不足！';
	END IF;
	
	-- ========== 4. 扣减景点剩余票数 ==========
	UPDATE Attraction A 
	SET A.remaining_tickets = A.remaining_tickets - p_quantity
	WHERE A.attraction_id = L_site_id;
	
	-- ========== 5. 获取门票关联的商品ID和价格 ==========
	SELECT AtT.product_id INTO L_product_id
	FROM Attraction_Ticket AtT WHERE AtT.ticket_id = p_ticket_id;
	
	-- 获取商品单价和默认折扣（避免嵌套子查询语法错误）
	SELECT P.unit_price, P.default_discount INTO L_unit_price, L_default_discount
	FROM Product P WHERE P.product_id = L_product_id;
	
	-- ========== 6. 生成订单ID（MySQL无OUTPUT，用自增/时间戳生成） ==========
	SELECT MAX(O.order_id) + 1 INTO L_order_id FROM Orders O;
	
	-- ========== 7. 插入订单主表 ==========
	INSERT INTO Orders(
		order_id, tourist_id, total_price, order_time, order_status, comment
	) VALUES (
		L_order_id, p_tourist_id, 0, NOW(), "已支付", "购票订单"
	);
	
	-- ========== 8. 插入订单明细表（修正子查询语法错误） ==========
	INSERT INTO OrderInfo(
		order_id, product_id, quantity, unit_price, discount, coupon_type, comment
	) VALUES (
		L_order_id,
		L_product_id,
		p_quantity,
		L_unit_price,
		L_default_discount,
		p_coupon_type,
		"景点门票订单"
	);
	
	-- ========== 9. 计算订单总金额（调用已有存储过程） ==========
	CALL CalcTotalPriceForOrder(L_order_id);
	
	-- ========== 10. 扣减优惠券（如果使用） ==========
	IF p_coupon_type IS NOT NULL THEN
		UPDATE TouristCoupon TC 
		SET TC.current_value = TC.current_value - p_quantity
		WHERE TC.tourist_id = p_tourist_id AND TC.coupon_type = p_coupon_type;
	END IF;
	
	-- ========== 11. 返回成功信息 ==========
	SELECT CONCAT(
		'购票成功！订单ID：', L_order_id, 
		'，景点ID：', L_site_id, 
		'，购票数量：', p_quantity
	) AS result;
	
END$$
DELIMITER ;


-- 执行完成提示
SELECT '数据库初始化完成！' AS result;