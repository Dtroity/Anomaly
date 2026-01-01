#!/bin/bash

echo "🔄 Обновление и исправление конфигурации Xray"
echo "=============================================="
echo ""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# 1. Обработка конфликтов git
echo "📥 Обновление кода из репозитория..."
if [ -n "$(git status --porcelain fix-xray-config.sh 2>/dev/null)" ]; then
    echo "  ⚠️  Обнаружены локальные изменения в fix-xray-config.sh"
    echo "  💾 Сохранение изменений в stash..."
    git stash push -m "Local changes to fix-xray-config.sh before update" fix-xray-config.sh 2>/dev/null || true
fi

# Обновление репозитория
git pull 2>&1 | grep -v "Already up to date" || true

# 2. Установка прав на выполнение
echo ""
echo "🔧 Установка прав на выполнение..."
chmod +x fix-xray-config.sh 2>/dev/null || true

# 3. Запуск скрипта исправления
echo ""
echo "🚀 Запуск скрипта исправления конфигурации..."
echo ""
./fix-xray-config.sh

