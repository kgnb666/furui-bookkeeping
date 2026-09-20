-- 大学生个人记账系统 数据库初始化脚本（Stage 1）
-- 依据：docs/项目设计文档-v1.0.md 第 11 章
-- 说明：脚本可重复执行（IF NOT EXISTS），不会删除已有数据

CREATE DATABASE IF NOT EXISTS campus_ledger
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

USE campus_ledger;

-- 1. 用户表
CREATE TABLE IF NOT EXISTS `user` (
  `id`         BIGINT       NOT NULL AUTO_INCREMENT              COMMENT '用户ID',
  `username`   VARCHAR(32)  NOT NULL                             COMMENT '登录名',
  `password`   VARCHAR(100) NOT NULL                             COMMENT 'BCrypt 加密后的密码',
  `nickname`   VARCHAR(32)  NOT NULL DEFAULT ''                  COMMENT '昵称',
  `email`      VARCHAR(64)      NULL                             COMMENT '邮箱（选填）',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_username` (`username`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '用户表';

-- 2. 导入批次表（bill 表引用它，因此先创建）
CREATE TABLE IF NOT EXISTS `import_batch` (
  `id`              BIGINT       NOT NULL AUTO_INCREMENT        COMMENT '批次ID',
  `user_id`         BIGINT       NOT NULL                       COMMENT '所属用户ID',
  `source`          VARCHAR(10)  NOT NULL                       COMMENT 'WECHAT / ALIPAY',
  `file_name`       VARCHAR(128) NOT NULL                       COMMENT '上传的账单文件名（仅展示）',
  `total_count`     INT          NOT NULL DEFAULT 0             COMMENT '解析出的总条数',
  `imported_count`  INT          NOT NULL DEFAULT 0             COMMENT '成功导入条数',
  `duplicate_count` INT          NOT NULL DEFAULT 0             COMMENT '重复跳过条数',
  `failed_count`    INT          NOT NULL DEFAULT 0             COMMENT '解析失败条数',
  `created_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_batch_user_created` (`user_id`, `created_at`),
  CONSTRAINT `fk_batch_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '账单导入批次表';

-- 3. 账单表
CREATE TABLE IF NOT EXISTS `bill` (
  `id`              BIGINT        NOT NULL AUTO_INCREMENT         COMMENT '账单ID',
  `user_id`         BIGINT        NOT NULL                        COMMENT '所属用户ID',
  `type`            TINYINT       NOT NULL                        COMMENT '1=支出 2=收入 3=不计收支',
  `amount`          DECIMAL(10,2) NOT NULL                        COMMENT '金额，恒为正数，方向由 type 决定',
  `category`        VARCHAR(20)   NOT NULL                        COMMENT '分类名称',
  `bill_date`       DATE          NOT NULL                        COMMENT '记账日期',
  `merchant`        VARCHAR(64)   NOT NULL DEFAULT ''             COMMENT '交易对象/商家',
  `remark`          VARCHAR(255)  NOT NULL DEFAULT ''             COMMENT '备注/商品说明',
  `source`          VARCHAR(10)   NOT NULL DEFAULT 'MANUAL'       COMMENT 'MANUAL=手动 WECHAT=微信 ALIPAY=支付宝',
  `source_trade_id` VARCHAR(64)       NULL                        COMMENT '平台原始交易号',
  `dedup_key`       VARCHAR(80) CHARACTER SET ascii NULL          COMMENT '去重键，手动记录为 NULL',
  `import_batch_id` BIGINT            NULL                        COMMENT '导入批次ID，手动记账为 NULL',
  `created_at`      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_bill_user_dedup`      (`user_id`, `dedup_key`),
  KEY        `idx_bill_user_date`      (`user_id`, `bill_date`),
  KEY        `idx_bill_user_type_date` (`user_id`, `type`, `bill_date`),
  KEY        `idx_bill_user_category`  (`user_id`, `category`),
  KEY        `idx_bill_user_source`    (`user_id`, `source`),
  KEY        `idx_bill_batch`          (`import_batch_id`),
  CONSTRAINT `fk_bill_user`  FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_bill_batch` FOREIGN KEY (`import_batch_id`) REFERENCES `import_batch` (`id`) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '账单表';

-- 4. 预算表
CREATE TABLE IF NOT EXISTS `budget` (
  `id`         BIGINT        NOT NULL AUTO_INCREMENT            COMMENT '预算ID',
  `user_id`    BIGINT        NOT NULL                           COMMENT '所属用户ID',
  `month`      CHAR(7)       NOT NULL                           COMMENT '预算月份，格式 yyyy-MM',
  `category`   VARCHAR(20)   NOT NULL DEFAULT ''                COMMENT '空串=月度总预算，否则为分类限额',
  `amount`     DECIMAL(10,2) NOT NULL                           COMMENT '预算金额',
  `created_at` DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_budget_user_month_category` (`user_id`, `month`, `category`),
  CONSTRAINT `fk_budget_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '预算表';
