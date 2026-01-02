#!/bin/bash
# Update code and fix users without proxies in Marzban

echo "🔄 Обновление кода и исправление пользователей"
echo "=============================================="

cd /opt/Anomaly || exit 1

# Handle git conflicts
if [ -n "$(git status --porcelain fix-users-without-proxies.sh 2>/dev/null)" ]; then
    echo "⚠️  Обнаружены локальные изменения в fix-users-without-proxies.sh"
    echo "💾 Сохранение изменений..."
    git stash push -m "Local changes to fix-users-without-proxies.sh" fix-users-without-proxies.sh 2>/dev/null || true
fi

# Update code
echo "📥 Обновление кода..."
git pull

# Restore stashed changes if any
if git stash list | grep -q "fix-users-without-proxies.sh"; then
    echo "📦 Восстановление локальных изменений..."
    git stash pop 2>/dev/null || true
fi

# Make script executable
chmod +x fix-users-without-proxies.sh

# Run the fix script
echo ""
echo "🔧 Запуск исправления пользователей..."
./fix-users-without-proxies.sh

