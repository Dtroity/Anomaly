#!/bin/bash
# Quick fix for users without proxies - handles git conflicts automatically

echo "🔄 Быстрое исправление пользователей без proxies"
echo "================================================"

cd /opt/Anomaly || exit 1

# Handle git conflicts for fix-users script
if git status --porcelain fix-users-without-proxies.sh 2>/dev/null | grep -q "fix-users-without-proxies.sh"; then
    echo "💾 Сохранение локальных изменений..."
    git stash push -m "Auto-stash fix-users script" fix-users-without-proxies.sh 2>/dev/null || true
fi

# Update code
echo "📥 Обновление кода..."
git pull

# Restore stashed changes if any
if git stash list 2>/dev/null | grep -q "fix-users-without-proxies"; then
    echo "📦 Восстановление изменений..."
    git stash pop 2>/dev/null || true
fi

# Make script executable
chmod +x fix-users-without-proxies.sh

# Run the fix script
echo ""
echo "🔧 Запуск исправления пользователей..."
./fix-users-without-proxies.sh

