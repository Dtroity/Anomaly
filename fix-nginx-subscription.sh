#!/bin/bash
# Fix Nginx subscription endpoint configuration

echo "🔧 Исправление конфигурации Nginx для subscription endpoint"
echo "============================================================"

cd /opt/Anomaly || exit 1

# Check if Marzban uses HTTPS
echo "📋 Проверка протокола Marzban..."
MARZBAN_SSL_CERT=$(docker exec anomaly-marzban env | grep "UVICORN_SSL_CERTFILE" | cut -d'=' -f2 | tr -d ' ' || echo "")

if [ -n "$MARZBAN_SSL_CERT" ] && [ "$MARZBAN_SSL_CERT" != "" ] && [ "$MARZBAN_SSL_CERT" != "''" ]; then
    echo "✅ Marzban использует HTTPS (сертификат: $MARZBAN_SSL_CERT)"
    PROXY_PASS="https://marzban:62050/sub/"
    PROXY_SSL="proxy_ssl_verify off;\n        proxy_ssl_server_name on;"
else
    echo "✅ Marzban использует HTTP"
    PROXY_PASS="http://marzban:62050/sub/"
    PROXY_SSL=""
fi

# Update Nginx configuration
echo ""
echo "📝 Обновление конфигурации Nginx..."

# Backup current config
cp nginx/conf.d/default.conf nginx/conf.d/default.conf.backup.$(date +%Y%m%d_%H%M%S)

# Update subscription location block
sed -i "s|proxy_pass http://marzban:62050/sub/;|proxy_pass ${PROXY_PASS};|" nginx/conf.d/default.conf

# Add SSL settings if needed (using printf for newlines)
if [ -n "$PROXY_SSL" ]; then
    if ! grep -q "proxy_ssl_verify" nginx/conf.d/default.conf; then
        # Use a temporary file for multi-line insertion
        awk -v ssl="$PROXY_SSL" '/proxy_set_header X-Forwarded-Proto \$scheme;/ {print; gsub(/\\\\n/, "\n", ssl); print "        " ssl; next}1' nginx/conf.d/default.conf > nginx/conf.d/default.conf.tmp
        mv nginx/conf.d/default.conf.tmp nginx/conf.d/default.conf
    fi
fi

# Add timeout settings
if ! grep -q "proxy_connect_timeout" nginx/conf.d/default.conf; then
    sed -i '/proxy_set_header X-Forwarded-Proto $scheme;/a\        proxy_connect_timeout 60s;\n        proxy_send_timeout 60s;\n        proxy_read_timeout 60s;' nginx/conf.d/default.conf
fi

echo "✅ Конфигурация обновлена"

# Test Nginx configuration
echo ""
echo "🧪 Проверка конфигурации Nginx..."
docker-compose exec nginx nginx -t

if [ $? -eq 0 ]; then
    echo ""
    echo "🔄 Перезагрузка Nginx..."
    docker-compose exec nginx nginx -s reload
    echo "✅ Nginx перезагружен"
else
    echo "❌ Ошибка в конфигурации Nginx"
    echo "💡 Восстановление из резервной копии..."
    # Restore backup logic here if needed
    exit 1
fi

echo ""
echo "✅ Готово!"
echo "💡 Проверьте subscription endpoint: ./check-subscription-endpoint.sh <token>"

