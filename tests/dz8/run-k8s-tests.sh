#!/bin/bash

# Запуск тестов
echo "Запуск интеграционных тестов для Kubernetes кластера..."
newman run dz8_postman_collection.json -e k8s-environment.json --timeout-request 60000 --delay-request 1000

# Проверка результата
if [ $? -eq 0 ]; then
    echo "✅ Все тесты успешно пройдены!"
else
    echo "❌ Некоторые тесты не пройдены!"
    exit 1
fi