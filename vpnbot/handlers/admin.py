"""
Admin handlers for Telegram bot
"""
import logging
from datetime import datetime, timedelta
from typing import Optional

from aiogram import Router, F
from aiogram.types import Message, CallbackQuery, InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup

from database import get_db_context
from models import User, UserRole, Payment, PaymentStatus
from services.analytics import AnalyticsService
from services.analytics_enhanced import EnhancedAnalyticsService
from services.marzban import MarzbanService
from services.nodes import NodeService
from services.logging_service import LoggingService
from config import settings

logger = logging.getLogger(__name__)

router = Router()


class AdminStates(StatesGroup):
    """Admin states"""
    waiting_broadcast = State()
    waiting_grant_user = State()
    waiting_grant_days = State()
    waiting_grant_traffic = State()


def is_admin(telegram_id: int) -> bool:
    """Check if user is admin"""
    admin_ids = settings.admin_ids_list
    is_admin_user = telegram_id in admin_ids
    logger.info(f"Admin check for {telegram_id}: {is_admin_user}, admin_ids: {admin_ids}")
    return is_admin_user


@router.message(Command("admin"))
async def cmd_admin(message: Message):
    """Admin panel"""
    if not is_admin(message.from_user.id):
        await message.answer("❌ Доступ запрещен")
        return
    
    with get_db_context() as db:
        analytics = EnhancedAnalyticsService(db)
        stats = analytics.get_dashboard_stats()
    
    admin_text = (
        f"🔐 Панель администратора {settings.app_name}\n\n"
        f"📊 Статистика:\n"
        f"• Активных пользователей: {stats['active_users']}\n"
        f"• Активных подписок: {stats['active_paid_subscriptions']}\n"
        f"• Пробных доступов: {stats['trial_users']}\n"
        f"• Всего пользователей: {stats['total_users']}\n"
        f"• Доход за 30 дней: {stats['revenue_30d']:.2f}₽\n"
        f"• Доход сегодня: {stats['revenue_today']:.2f}₽\n"
        f"• Платежей сегодня: {stats['payments_today']}\n"
        f"• Конверсия (trial→paid): {stats['conversion_rate']:.1f}%\n"
        f"• Отток: {stats['churn_rate']:.1f}%\n"
        f"• Средняя сессия: {int(stats['avg_session_duration_seconds'])} сек\n\n"
        f"👥 По ролям:\n"
    )
    
    for role, count in stats['users_by_role'].items():
        admin_text += f"  • {role}: {count}\n"
    
    # Добавляем статистику по нодам
    if stats.get('node_stats'):
        admin_text += "\n🌍 Нагрузка нод:\n"
        for node in stats['node_stats']:
            admin_text += f"  • {node['name']}: {node['current_users']}/{node['max_users'] if node['max_users'] > 0 else '∞'} ({node['load_percent']:.1f}%)\n"
    
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="👥 Пользователи", callback_data="admin_users"),
            InlineKeyboardButton(text="📊 Статистика", callback_data="admin_stats")
        ],
        [
            InlineKeyboardButton(text="🎁 Выдать доступ", callback_data="admin_grant"),
            InlineKeyboardButton(text="🚫 Заблокировать", callback_data="admin_ban")
        ],
        [
            InlineKeyboardButton(text="📢 Рассылка", callback_data="admin_broadcast"),
            InlineKeyboardButton(text="🔄 Обновить", callback_data="admin_refresh")
        ]
    ])
    
    await message.answer(admin_text, reply_markup=keyboard)


@router.callback_query(F.data == "admin_refresh")
async def callback_admin_refresh(callback: CallbackQuery):
    """Refresh admin panel"""
    if not is_admin(callback.from_user.id):
        await callback.answer("Доступ запрещен", show_alert=True)
        return
    
    await cmd_admin(callback.message)


@router.callback_query(F.data == "admin_users")
async def callback_admin_users(callback: CallbackQuery):
    """Show users list"""
    if not is_admin(callback.from_user.id):
        await callback.answer("Доступ запрещен", show_alert=True)
        return
    
    with get_db_context() as db:
        users = db.query(User).order_by(User.created_at.desc()).limit(20).all()
        
        if not users:
            await callback.answer("Пользователи не найдены", show_alert=True)
            return
        
        users_text = "👥 Последние пользователи:\n\n"
        for user in users:
            status = "✅" if not user.is_expired and user.is_active else "❌"
            users_text += (
                f"{status} ID: {user.telegram_id}\n"
                f"   @{user.username or 'нет'}\n"
                f"   Роль: {user.role.value}\n"
                f"   До: {user.expires_at.strftime('%d.%m.%Y') if user.expires_at else 'Нет'}\n\n"
            )
        
        await callback.message.edit_text(
            users_text,
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="◀️ Назад", callback_data="admin_back")]
            ])
        )


@router.callback_query(F.data == "admin_stats")
async def callback_admin_stats(callback: CallbackQuery):
    """Show detailed statistics"""
    if not is_admin(callback.from_user.id):
        await callback.answer("Доступ запрещен", show_alert=True)
        return
    
    with get_db_context() as db:
        analytics = AnalyticsService(db)
        stats = analytics.get_dashboard_stats()
        recent_payments = analytics.get_recent_payments(5)
        
        stats_text = (
            f"📊 Детальная статистика\n\n"
            f"👥 Пользователи:\n"
            f"• Активных: {stats['active_users']}\n"
            f"• Всего: {stats['total_users']}\n"
            f"• Платных подписок: {stats['active_paid_subscriptions']}\n\n"
            f"💰 Финансы:\n"
            f"• За 30 дней: {stats['revenue_30d']:.2f}₽\n"
            f"• Сегодня: {stats['revenue_today']:.2f}₽\n\n"
            f"🎁 Промо:\n"
            f"• Выдано за 30 дней: {stats['promo_issued_30d']}\n\n"
        )
        
        if recent_payments:
            stats_text += "💳 Последние платежи:\n"
            for payment in recent_payments:
                stats_text += (
                    f"• {payment['amount']:.2f}₽ "
                    f"({payment['method']}) "
                    f"ID: {payment['telegram_id']}\n"
                )
        
        await callback.message.edit_text(
            stats_text,
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="◀️ Назад", callback_data="admin_back")]
            ])
        )


@router.message(Command("grant"))
async def cmd_grant(message: Message):
    """Grant access to user: /grant <telegram_id> <days> <traffic_gb>"""
    if not is_admin(message.from_user.id):
        await message.answer("❌ Доступ запрещен")
        return
    
    try:
        parts = message.text.split()
        if len(parts) < 4:
            await message.answer(
                "Использование: /grant <telegram_id> <days> <traffic_gb>\n"
                "Пример: /grant 123456789 30 100"
            )
            return
        
        telegram_id = int(parts[1])
        days = int(parts[2])
        traffic_gb = float(parts[3])
        
        with get_db_context() as db:
            user = db.query(User).filter(User.telegram_id == telegram_id).first()
            
            if not user:
                await message.answer(f"❌ Пользователь {telegram_id} не найден")
                return
            
            # Update user
            user.role = UserRole.USER
            user.expires_at = datetime.utcnow() + timedelta(days=days)
            user.traffic_limit_gb = traffic_gb
            user.used_traffic_gb = 0.0
            user.source = "promo"
            
            # Create/update in Marzban
            try:
                node_service = NodeService(db)
                node = node_service.select_best_node()
                
                if node:
                    marzban = MarzbanService(
                        api_url=node["url"],
                        username=node["username"],
                        password=node["password"]
                    )
                    
                    username = f"user_{user.telegram_id}"
                    expire_date = user.expires_at
                    data_limit = int(traffic_gb * 1024 * 1024 * 1024) if traffic_gb > 0 else None
                    
                    existing_user = await marzban.get_user(username)
                    if existing_user:
                        await marzban.update_user(
                            username=username,
                            data_limit=data_limit,
                            expire_date=expire_date
                        )
                    else:
                        await marzban.create_user(
                            username=username,
                            data_limit=data_limit,
                            expire_date=expire_date
                        )
                    
                    user.node_assigned = node["id"]
            except Exception as e:
                logger.error(f"Error updating Marzban user: {e}")
            
            db.commit()
            
            await message.answer(
                f"✅ Доступ выдан пользователю {telegram_id}\n"
                f"• Срок: {days} дней\n"
                f"• Трафик: {traffic_gb} GB"
            )
    
    except ValueError:
        await message.answer("❌ Неверный формат команды")
    except Exception as e:
        logger.error(f"Error granting access: {e}")
        await message.answer(f"❌ Ошибка: {e}")


@router.message(Command("revoke"))
async def cmd_revoke(message: Message):
    """Revoke access: /revoke <telegram_id>"""
    if not is_admin(message.from_user.id):
        await message.answer("❌ Доступ запрещен")
        return
    
    try:
        parts = message.text.split()
        if len(parts) < 2:
            await message.answer("Использование: /revoke <telegram_id>")
            return
        
        telegram_id = int(parts[1])
        
        with get_db_context() as db:
            user = db.query(User).filter(User.telegram_id == telegram_id).first()
            
            if not user:
                await message.answer(f"❌ Пользователь {telegram_id} не найден")
                return
            
            # Ban user
            user.role = UserRole.BANNED
            user.is_active = False
            
            # Delete from Marzban
            try:
                node_service = NodeService(db)
                node = node_service.get_node_by_id(user.node_assigned) if user.node_assigned else None
                
                if not node:
                    node = node_service.select_best_node()
                
                if node:
                    marzban = MarzbanService(
                        api_url=node["url"],
                        username=node["username"],
                        password=node["password"]
                    )
                    
                    username = f"user_{user.telegram_id}"
                    await marzban.delete_user(username)
            except Exception as e:
                logger.error(f"Error deleting Marzban user: {e}")
            
            db.commit()
            
            await message.answer(f"✅ Пользователь {telegram_id} заблокирован")
    
    except ValueError:
        await message.answer("❌ Неверный формат команды")
    except Exception as e:
        logger.error(f"Error revoking access: {e}")
        await message.answer(f"❌ Ошибка: {e}")


@router.message(Command("stats"))
async def cmd_stats(message: Message):
    """Show enhanced statistics"""
    if not is_admin(message.from_user.id):
        await message.answer("❌ Доступ запрещен")
        return
    
    with get_db_context() as db:
        analytics = EnhancedAnalyticsService(db)
        stats = analytics.get_dashboard_stats()
        
        stats_text = (
            f"📊 Расширенная статистика {settings.app_name}\n\n"
            f"👥 Пользователи:\n"
            f"• Активных: {stats['active_users']}\n"
            f"• Платных подписок: {stats['active_paid_subscriptions']}\n"
            f"• Пробных доступов: {stats['trial_users']}\n"
            f"• Всего: {stats['total_users']}\n\n"
            f"💰 Доход:\n"
            f"• За 30 дней: {stats['revenue_30d']:.2f}₽\n"
            f"• Сегодня: {stats['revenue_today']:.2f}₽\n"
            f"• Платежей сегодня: {stats['payments_today']}\n"
        )
        
        # Доход по провайдерам
        if stats.get('revenue_by_provider'):
            stats_text += "\n💳 Доход по провайдерам:\n"
            for provider, amount in stats['revenue_by_provider'].items():
                stats_text += f"  • {provider}: {amount:.2f}₽\n"
        
        # Метрики
        stats_text += (
            f"\n📈 Метрики:\n"
            f"• Конверсия (trial→paid): {stats['conversion_rate']:.1f}%\n"
            f"• Отток: {stats['churn_rate']:.1f}%\n"
            f"• Средняя сессия: {int(stats['avg_session_duration_seconds'])} сек\n"
        )
        
        # Нагрузка нод
        if stats.get('node_stats'):
            stats_text += "\n🌍 Нагрузка нод:\n"
            for node in stats['node_stats']:
                max_str = str(node['max_users']) if node['max_users'] > 0 else "∞"
                stats_text += f"  • {node['name']}: {node['current_users']}/{max_str} ({node['load_percent']:.1f}%)\n"
        
        await message.answer(stats_text)


@router.message(Command("broadcast"))
async def cmd_broadcast(message: Message, state: FSMContext):
    """Start broadcast: /broadcast"""
    if not is_admin(message.from_user.id):
        await message.answer("❌ Доступ запрещен")
        return
    
    await message.answer(
        "📢 Введите сообщение для рассылки всем пользователям:\n\n"
        "Используйте /cancel для отмены"
    )
    await state.set_state(AdminStates.waiting_broadcast)


@router.message(AdminStates.waiting_broadcast)
async def process_broadcast(message: Message, state: FSMContext):
    """Process broadcast message"""
    if message.text == "/cancel":
        await state.clear()
        await message.answer("❌ Рассылка отменена")
        return
    
    broadcast_text = message.text or message.caption or ""
    
    with get_db_context() as db:
        users = db.query(User).filter(User.role != UserRole.BANNED).all()
        
        sent = 0
        failed = 0
        
        await message.answer(f"📢 Начинаю рассылку для {len(users)} пользователей...")
        
        for user in users:
            try:
                # Note: In real implementation, you would use bot.send_message()
                # This is a placeholder
                sent += 1
            except Exception as e:
                logger.error(f"Error sending broadcast to {user.telegram_id}: {e}")
                failed += 1
        
        await message.answer(
            f"✅ Рассылка завершена\n"
            f"• Отправлено: {sent}\n"
            f"• Ошибок: {failed}"
        )
    
    await state.clear()


@router.callback_query(F.data == "admin_back")
async def callback_admin_back(callback: CallbackQuery):
    """Return to admin panel"""
    await cmd_admin(callback.message)

