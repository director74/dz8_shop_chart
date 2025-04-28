# Схема очередей RabbitMQ в системе

В данном документе описана схема очередей RabbitMQ и механизм обмена сообщениями между микросервисами, включая паттерн Saga.

## Основные компоненты

### Exchanges:
- `saga_exchange` (тип: topic) - основной обмен для сообщений саги (шаги, результаты, компенсации).
- `order_events` (тип: topic) - обмен для событий, связанных с заказами (создание, ошибка, отмена). Используется для уведомлений.
- `billing_events` (тип: topic) - обмен для событий биллинга (пополнение, недостаток средств). Используется для уведомлений.

### Очереди и привязки по сервисам

#### Order Service (Оркестратор саги):
- **Слушает:**
    - Очередь: `order_service.saga_results`
    - Привязка: `saga_exchange` -> `saga.*.result` (Получает результаты всех шагов саги)
- **Публикует:**
    - В `saga_exchange`:
        - `saga.<step>.execute` (Запуск выполнения шага)
        - `saga.<step>.compensate` (Запуск компенсации шага)
    - В `order_events`:
        - `order.notification` (При успешном старте саги)
        - `order.failed` (При ошибке шага саги и инициации компенсации)
        - `order.cancelled` (При успешном завершении компенсации)

#### Billing Service:
- **Слушает:**
    - Очередь: `billing_process_queue` (Привязка: `saga_exchange` -> `saga.process_billing.execute`)
    - Очередь: `billing_compensate_queue` (Привязка: `saga_exchange` -> `saga.process_billing.compensate`)
- **Публикует:**
    - В `saga_exchange`:
        - `saga.process_billing.result` (Статус: `completed`/`failed`/`compensated`)
    - В `billing_events`:
        - `billing.deposit`
        - `billing.insufficient_funds`
        - (Другие события биллинга...)

#### Payment Service:
- **Слушает:**
    - Очередь: `payment_process_queue` (Привязка: `saga_exchange` -> `saga.process_payment.execute`)
    - Очередь: `payment_compensate_queue` (Привязка: `saga_exchange` -> `saga.process_payment.compensate`)
- **Публикует:**
    - В `saga_exchange`:
        - `saga.process_payment.result` (Статус: `completed`/`failed`/`compensated`)

#### Warehouse Service:
- **Слушает:**
    - Очередь: `warehouse_reserve_queue` (Привязка: `saga_exchange` -> `saga.reserve_warehouse.execute`)
    - Очередь: `warehouse_compensate_queue` (Привязка: `saga_exchange` -> `saga.reserve_warehouse.compensate`)
- **Публикует:**
    - В `saga_exchange`:
        - `saga.reserve_warehouse.result` (Статус: `completed`/`failed`/`compensated`)

#### Delivery Service:
- **Слушает:**
    - Очередь: `delivery_reserve_queue` (Привязка: `saga_exchange` -> `saga.reserve_delivery.execute`)
    - Очередь: `delivery_compensate_queue` (Привязка: `saga_exchange` -> `saga.reserve_delivery.compensate`)
- **Публикует:**
    - В `saga_exchange`:
        - `saga.reserve_delivery.result` (Статус: `completed`/`failed`/`compensated`)

#### Notification Service:
- **Слушает:**
    - Очередь: `notification_saga_queue` (Привязка: `saga_exchange` -> `saga.notify_customer.execute`) - Шаг саги
    - Очередь: `order_notifications` (Привязка: `order_events` -> `order.notification`) - Событие создания
    - Очередь: `deposit_notifications` (Привязка: `billing_events` -> `billing.deposit`) - Событие пополнения
    - Очередь: `insufficient_funds_notifications` (Привязка: `billing_events` -> `billing.insufficient_funds`) - Событие недостатка средств
    - Очередь: `order_cancellation_notifications` (Привязки: `order_events` -> `order.cancelled` и `order.failed`) - События отмены/ошибки
- **Публикует:**
    - В `saga_exchange`:
        - `saga.notify_customer.result` (Статус: `completed`/`failed`)

## Схема работы оркестратора саги

### Оркестратор (Order Service):
- Определяет последовательность шагов саги:
  1. `create_order` (внутренний шаг, не через RabbitMQ)
  2. `process_billing`
  3. `process_payment`
  4. `reserve_warehouse`
  5. `reserve_delivery`
  6. `confirm_order` (внутренний шаг)
  7. `notify_customer`

- **Публикация сообщений:**
  - При старте саги (после `create_order`): Отправляет `saga.process_billing.execute` в `saga_exchange`.
  - При успешном получении результата шага: Отправляет `saga.<следующий_шаг>.execute` в `saga_exchange`.
  - При получении результата со статусом `failed` или `compensated` (для шага `execute`), или `failed` (для шага `compensate`):
    - Отправляет `order.failed` в `order_events`.
    - Запускает компенсацию: отправляет `saga.<предыдущий_шаг>.compensate` в `saga_exchange` для всех пройденных компенсируемых шагов.
  - При успешном завершении всех шагов компенсации:
    - Отправляет `order.cancelled` в `order_events`.

- **Получение сообщений:**
  - Из очереди `order_service.saga_results` (ключ `saga.*.result`). Обрабатывает результаты (`completed`, `failed`, `compensated`) и принимает решение о следующем шаге или компенсации.

### Каждый сервис-участник саги (Billing, Payment, Warehouse, Delivery, Notification):
- Имеет обработчик(и) для выполнения основного действия (`execute`).
- Сервисы с компенсируемыми шагами (Billing, Payment, Warehouse, Delivery) также имеют обработчик для компенсации (`compensate`).
- **При обработке `execute`:**
  - Выполняет действие.
  - Публикует результат `saga.<имя_шага>.result` в `saga_exchange` со статусом `completed` или `failed`.
- **При обработке `compensate`:**
  - Выполняет компенсирующее действие.
  - Публикует результат `saga.<имя_шага>.result` в `saga_exchange` со статусом `compensated` или `failed`.

## Последовательность работы саги (успешный сценарий)

1. Order Service создает заказ в БД, сохраняет начальное состояние саги.
2. Оркестратор публикует `saga.process_billing.execute`.
3. Billing Service получает сообщение, обрабатывает, публикует `saga.process_billing.result` (status: `completed`).
4. Оркестратор получает результат, публикует `saga.process_payment.execute`.
5. Payment Service получает сообщение, обрабатывает, публикует `saga.process_payment.result` (status: `completed`).
6. Оркестратор получает результат, публикует `saga.reserve_warehouse.execute`.
7. Warehouse Service получает сообщение, обрабатывает, публикует `saga.reserve_warehouse.result` (status: `completed`).
8. Оркестратор получает результат, публикует `saga.reserve_delivery.execute`.
9. Delivery Service получает сообщение, обрабатывает, публикует `saga.reserve_delivery.result` (status: `completed`).
10. Оркестратор получает результат, выполняет внутренний шаг `confirm_order` (меняет статус заказа в БД).
11. Оркестратор публикует `saga.notify_customer.execute`.
12. Notification Service получает сообщение, "отправляет" уведомление, публикует `saga.notify_customer.result` (status: `completed`).
13. Оркестратор получает результат, меняет статус заказа и саги на `Completed`, удаляет состояние саги.

## Сценарий с ошибкой и компенсацией (пример: ошибка на шаге Delivery)

1. ... Шаги 1-9 проходят успешно ...
2. Delivery Service получает `saga.reserve_delivery.execute`, но не может выполнить резервирование. Публикует `saga.reserve_delivery.result` (status: `failed`, error: "слот недоступен").
3. Оркестратор получает результат (`failed`):
   - Публикует `order.failed` в `order_events`.
   - Меняет статус саги на `compensating`.
   - Публикует `saga.reserve_warehouse.compensate`.
   - Публикует `saga.process_payment.compensate`.
   - Публикует `saga.process_billing.compensate`.
4. Warehouse Service получает `compensate`, отменяет резерв, публикует `saga.reserve_warehouse.result` (status: `compensated`).
5. Payment Service получает `compensate`, отменяет платеж, публикует `saga.process_payment.result` (status: `compensated`).
6. Billing Service получает `compensate`, отменяет списание, публикует `saga.process_billing.result` (status: `compensated`).
7. Оркестратор получает все три результата `compensated`:
   - Меняет статус саги на `Compensated`.
   - Публикует `order.cancelled` в `order_events`.
   - Удаляет состояние саги.

Эта архитектура обеспечивает надежное выполнение распределенных транзакций с возможностью компенсации в случае ошибок. 