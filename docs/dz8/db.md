# Организация баз данных PostgreSQL в проекте

## Базы данных и таблицы

### 1. Order Service

*   **Под:** `postgres`
*   **База данных:** `orders`
*   **Основные таблицы:**
    *   `users`: Информация о пользователях.
    *   `orders`: Информация о заказах (`id`, `user_id`, `amount`, `status`, `created_at`, `updated_at`).
    *   `order_items`: Товары в заказе (`order_id`, `product_id`, `quantity`, `price`).
    *   `saga_states`: Состояние саги для заказов (`saga_id`, `order_id`, `status`, `compensated_steps` (jsonb), `total_to_compensate`, `last_step`, `error_message`, `created_at`, `updated_at`).

### 2. Billing Service

*   **Под:** `postgres`
*   **База данных:** `billing`
*   **Основные таблицы:**
    *   `accounts`: Счета пользователей (`id`, `user_id`, `balance`, `created_at`, `updated_at`).
    *   `transactions`: Транзакции по счетам (`id`, `account_id`, `amount`, `type` (character varying), `status` (character varying), `created_at`, `updated_at`).

### 3. Notification Service

*   **Под:** `postgres`
*   **База данных:** `notifications`
*   **Основные таблицы:**
    *   `notifications`: Уведомления (`id`, `user_id`, `email`, `subject`, `message`, `status` (text), `created_at`, `updated_at`).

### 4. Delivery Service

*   **Под:** `delivery-db`
*   **База данных:** `delivery`
*   **Основные таблицы:**
    *   `delivery`: Информация о доставках (`id`, `order_id`, `user_id`, `courier_id`, `status`, `delivery_address`, `scheduled_start_time`, `scheduled_end_time`, `recipient_name`, `recipient_phone`, `created_at`, `updated_at`).
    *   `couriers`: Информация о курьерах.
    *   `delivery_slots`: Доступные слоты доставки.
    *   `courier_schedules`: Расписание курьеров.
    *   `delivery_zones`: Зоны доставки.

### 5. Warehouse Service

*   **Под:** `warehouse-db`
*   **База данных:** `warehouse`
*   **Основные таблицы:**
    *   `products`: Информация о товарах (`id`, `name`, `description`, `price`, `sku`, `created_at`, `updated_at`).
    *   `warehouse_items`: Наличие товаров на складе (`id`, `product_id`, `quantity`, `reserved_quantity`, `available` (generated), `location`, `name`, `sku`, `price`, `status`, `created_at`, `updated_at`)
    *   `warehouse_reservations`: Резервы товаров для заказов (`id`, `order_id`, `product_id`, `warehouse_item_id`, `quantity`, `status`, `created_at`, `updated_at`, `expires_at`).

### 6. Payment Service

*   **Под:** `payment-db`
*   **База данных:** `payments`
*   **Основные таблицы:**
    *   `payments`: Информация о платежах (`id`, `order_id`, `user_id`, `amount`, `payment_method`, `status`, `transaction_id`, `created_at`, `updated_at`).
    *   `payment_methods`: Способы оплаты.

**Примечание:** Имена баз данных для `delivery-db`, `warehouse-db` и `payment-db` подтверждены как `delivery`, `warehouse`, `payments`. Структура некоторых второстепенных таблиц (например, `couriers`, `payment_methods`) не проверялась. Если подключение к ним не удастся, используйте команду `docker exec -it <container_name> bash -c 'PGPASSWORD=password psql -U postgres -d <db_name> -c "\l"' | cat` для просмотра списка баз данных в соответствующем контейнере. 