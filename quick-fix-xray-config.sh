#!/bin/bash

echo "🔧 Быстрое исправление конфигурации Xray"
echo "========================================="
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# 1. Обновление кода
echo "📥 Обновление кода..."
git pull 2>&1 | grep -v "Already up to date" || true

# 2. Установка прав
echo ""
echo "🔧 Установка прав на выполнение..."
chmod +x fix-xray-config.sh update-and-fix-xray-config.sh 2>/dev/null || true

# 3. Запуск исправления
echo ""
echo "🚀 Запуск исправления конфигурации..."
echo ""
if [ -f "fix-xray-config.sh" ]; then
    ./fix-xray-config.sh
else
    echo "❌ Скрипт fix-xray-config.sh не найден"
    echo "💡 Попробуйте: git pull"
    exit 1
fi

