#!/bin/bash

# Читаем URL из переменных окружения или используем localhost по умолчанию
ES_URL=${ELASTICSEARCH_URL:-"http://localhost:9200"}
INDEX_NAME="performers"
MAPPING_FILE="es_performers_mapping.json"
SEED_FILE="performers_seed.ndjson"

echo "[*] Ожидание запуска ElasticSearch по адресу $ES_URL..."
# Пингуем health-check пока ES не ответит (удобно при деплое через docker-compose)
until curl -s "$ES_URL/_cluster/health" > /dev/null; do
  echo "Ожидание..."
  sleep 2
done
echo "[+] ElasticSearch доступен!"

echo "[*] Удаление старого индекса (если существует)..."
curl -s -X DELETE "$ES_URL/$INDEX_NAME" > /dev/null
echo ""

echo "[*] Создание индекса '$INDEX_NAME' с настройками и маппингом..."
curl -s -X PUT "$ES_URL/$INDEX_NAME" -H 'Content-Type: application/json' -d @"$MAPPING_FILE"
echo ""

echo "[*] Загрузка начальных данных (сидов) через Bulk API..."
# Для _bulk запросов обязательно использование application/x-ndjson и --data-binary
curl -s -X POST "$ES_URL/_bulk" -H 'Content-Type: application/x-ndjson' --data-binary @"$SEED_FILE"
echo ""

echo "[+] Инициализация ElasticSearch завершена!"
