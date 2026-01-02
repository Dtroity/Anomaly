"""
User handlers for Telegram bot
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
from models import User, UserRole, SubscriptionPlan
from services.marzban import MarzbanService
from services.nodes import NodeService
from services.payment_provider import PaymentService, PaymentProviderType
from services.telegram_pay import TelegramPayService
from services.trial_service import TrialService
from services.logging_service import LoggingService
from config import settings

logger = logging.getLogger(__name__)

router = Router()


class PaymentStates(StatesGroup):
    """Payment flow states"""
    selecting_plan = State()
    selecting_payment_method = State()
    waiting_payment = State()


def get_user_keyboard(show_trial: bool = False) -> InlineKeyboardMarkup:
    """Get main user keyboard"""
    buttons = [
        [
            InlineKeyboardButton(text="🔗 Подключиться", callback_data="connect"),
            InlineKeyboardButton(text="📊 Статус", callback_data="status")
        ],
        [
            InlineKeyboardButton(text="💳 Купить подписку", callback_data="buy"),
            InlineKeyboardButton(text="❓ Помощь", callback_data="help")
        ]
    ]
    
    if show_trial:
        buttons.insert(1, [
            InlineKeyboardButton(text="🎁 Получить пробный доступ", callback_data="trial")
        ])
    
    return InlineKeyboardMarkup(inline_keyboard=buttons)


@router.message(Command("start"))
async def cmd_start(message: Message):
    """Handle /start command"""
    with get_db_context() as db:
        # Check if user exists
        user = db.query(User).filter(User.telegram_id == message.from_user.id).first()
        
        if not user:
            # Create new user
            user = User(
                telegram_id=message.from_user.id,
                username=message.from_user.username,
                first_name=message.from_user.first_name,
                last_name=message.from_user.last_name,
                role=UserRole.PROMO,
                source="manual"
            )
            db.add(user)
            db.commit()
            db.refresh(user)
            
            # Логируем регистрацию
            logging_service = LoggingService(db)
            logging_service.log_user_action(user, "registered")
        
        # Проверяем, может ли пользователь получить пробный доступ
        trial_service = TrialService(db)
        show_trial = trial_service.check_trial_eligibility(user)
        
        welcome_text = (
            f"👋 Добро пожаловать в {settings.app_name}!\n\n"
            "🔐 Безопасный доступ к сервису\n"
            "⚡ Высокая скорость подключения\n"
            "🌍 Доступ из любой точки мира\n\n"
        )
        
        if show_trial:
            welcome_text += "🎁 Доступен пробный период!\n\n"
        
        welcome_text += "Выберите действие:"
        
        await message.answer(
            welcome_text,
            reply_markup=get_user_keyboard(show_trial=show_trial)
        )


@router.callback_query(F.data == "connect")
async def callback_connect(callback: CallbackQuery):
    """Handle connect button"""
    with get_db_context() as db:
        user = db.query(User).filter(User.telegram_id == callback.from_user.id).first()
        
        if not user:
            await callback.answer("Пожалуйста, начните с команды /start", show_alert=True)
            return
        
        # Check if user is banned
        if user.role == UserRole.BANNED:
            await callback.answer("Ваш доступ заблокирован", show_alert=True)
            return
        
        # Check if expired
        if user.is_expired:
            await callback.answer(
                "Ваша подписка истекла. Пожалуйста, продлите доступ.",
                show_alert=True
            )
            await callback.message.edit_text(
                "❌ Ваша подписка истекла.\n\n"
                "Для продолжения работы необходимо продлить доступ.",
                reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                    [InlineKeyboardButton(text="💳 Купить подписку", callback_data="buy")]
                ])
            )
            return
        
        # Check traffic
        if user.is_traffic_exceeded:
            await callback.answer(
                "Лимит трафика исчерпан. Пожалуйста, продлите доступ.",
                show_alert=True
            )
            return
        
        # Get or create Marzban user
        try:
            node_service = NodeService(db)
            node = node_service.select_best_node()
            
            if not node:
                await callback.answer("Ошибка: нет доступных серверов", show_alert=True)
                return
            
            marzban = MarzbanService(
                api_url=node["url"],
                username=node["username"],
                password=node["password"]
            )
            
            username = f"user_{user.telegram_id}"
            
            # Check if user exists in Marzban
            marzban_user = await marzban.get_user(username)
            
            if not marzban_user:
                # Create new user
                expire_date = user.expires_at if user.expires_at else datetime.utcnow() + timedelta(days=30)
                data_limit = int(user.traffic_limit_gb * 1024 * 1024 * 1024) if user.traffic_limit_gb > 0 else None
                
                marzban_user = await marzban.create_user(
                    username=username,
                    data_limit=data_limit,
                    expire_date=expire_date
                )
            
            # Update user in database
            user.node_assigned = node["id"]
            user.marzban_uuid = marzban_user.get("uuid")
            user.last_active = datetime.utcnow()
            db.commit()
            
            # Get connection link (subscription URL)
            subscription = marzban_user.get("subscription_url") or await marzban.get_subscription_url(username)
            
            if subscription:
                connection_text = (
                    f"✅ Подключение готово!\n\n"
                    f"📱 Ваш ключ доступа:\n"
                    f"`{subscription}`\n\n"
                    f"📊 Статус:\n"
                    f"• Действует до: {user.expires_at.strftime('%d.%m.%Y %H:%M') if user.expires_at else 'Не ограничено'}\n"
                    f"• Трафик: {user.used_traffic_gb:.2f} / {user.traffic_limit_gb:.2f} GB\n"
                    f"• Устройства: до {user.max_devices}\n\n"
                    f"💡 Инструкция по настройке: /help"
                )
                
                await callback.message.edit_text(
                    connection_text,
                    reply_markup=get_user_keyboard(),
                    parse_mode="Markdown"
                )
            else:
                await callback.answer("Ошибка получения ключа", show_alert=True)
        
        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error connecting user {user.telegram_id}: {e}")
            
            # Provide user-friendly error messages (keep them short to avoid MESSAGE_TOO_LONG)
            if "No proxy protocols available" in error_msg or "Could not determine available protocols" in error_msg:
                user_msg = "❌ Протоколы VPN не настроены. Настройте inbounds в панели Marzban"
            elif "Protocol" in error_msg and "disabled" in error_msg:
                user_msg = "❌ Протокол VPN отключен. Настройте inbounds в панели"
            else:
                # Limit error message to 100 characters to avoid MESSAGE_TOO_LONG
                user_msg = f"Ошибка: {error_msg[:80]}"
            
            # Telegram alert messages have a limit of 200 characters
            # Truncate if necessary (use 100 to be safe)
            if len(user_msg) > 100:
                user_msg = user_msg[:97] + "..."
            
            await callback.answer(user_msg, show_alert=True)


@router.callback_query(F.data == "status")
async def callback_status(callback: CallbackQuery):
    """Handle status button"""
    with get_db_context() as db:
        user = db.query(User).filter(User.telegram_id == callback.from_user.id).first()
        
        if not user:
            await callback.answer("Пользователь не найден", show_alert=True)
            return
        
        status_text = (
            f"📊 Ваш статус\n\n"
            f"👤 Роль: {user.role.value}\n"
            f"📅 Подписка до: {user.expires_at.strftime('%d.%m.%Y %H:%M') if user.expires_at else 'Не ограничено'}\n"
            f"📊 Трафик: {user.used_traffic_gb:.2f} / {user.traffic_limit_gb:.2f} GB\n"
            f"📱 Устройства: до {user.max_devices}\n"
            f"🔄 Последняя активность: {user.last_active.strftime('%d.%m.%Y %H:%M') if user.last_active else 'Никогда'}\n"
        )
        
        if user.is_expired:
            status_text += "\n❌ Подписка истекла"
        elif user.is_traffic_exceeded:
            status_text += "\n⚠️ Лимит трафика исчерпан"
        else:
            status_text += "\n✅ Активна"
        
        await callback.message.edit_text(
            status_text,
            reply_markup=get_user_keyboard()
        )


@router.callback_query(F.data == "buy")
async def callback_buy(callback: CallbackQuery, state: FSMContext):
    """Handle buy button"""
    with get_db_context() as db:
        # Get available plans
        plans = db.query(SubscriptionPlan).filter(SubscriptionPlan.is_active == True).all()
        
        if not plans:
            # Create default plans if none exist
            default_plans = [
                SubscriptionPlan(
                    name="Базовый",
                    description="30 дней, 100 GB",
                    duration_days=30,
                    traffic_limit_gb=100,
                    max_devices=3,
                    price=299.0,
                    currency="RUB"
                ),
                SubscriptionPlan(
                    name="Стандарт",
                    description="30 дней, 200 GB",
                    duration_days=30,
                    traffic_limit_gb=200,
                    max_devices=5,
                    price=499.0,
                    currency="RUB"
                ),
                SubscriptionPlan(
                    name="Премиум",
                    description="30 дней, безлимит",
                    duration_days=30,
                    traffic_limit_gb=0,  # 0 = unlimited
                    max_devices=10,
                    price=799.0,
                    currency="RUB"
                )
            ]
            for plan in default_plans:
                db.add(plan)
            db.commit()
            plans = default_plans
        
        # Create keyboard with plans
        keyboard_buttons = []
        for plan in plans:
            traffic_text = "Безлимит" if plan.traffic_limit_gb == 0 else f"{plan.traffic_limit_gb} GB"
            button_text = f"{plan.name} - {plan.price}₽ ({plan.duration_days} дн., {traffic_text})"
            keyboard_buttons.append([
                InlineKeyboardButton(
                    text=button_text,
                    callback_data=f"plan_{plan.id}"
                )
            ])
        
        keyboard_buttons.append([
            InlineKeyboardButton(text="◀️ Назад", callback_data="back_to_main")
        ])
        
        plans_text = "💳 Выберите тариф:\n\n"
        for plan in plans:
            traffic_text = "Безлимит" if plan.traffic_limit_gb == 0 else f"{plan.traffic_limit_gb} GB"
            plans_text += (
                f"• {plan.name}\n"
                f"  {plan.duration_days} дней, {traffic_text}, до {plan.max_devices} устройств\n"
                f"  💰 {plan.price}₽\n\n"
            )
        
        await callback.message.edit_text(
            plans_text,
            reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard_buttons)
        )
        await state.set_state(PaymentStates.selecting_plan)


@router.callback_query(F.data.startswith("plan_"))
async def callback_select_plan(callback: CallbackQuery, state: FSMContext):
    """Handle plan selection"""
    plan_id = int(callback.data.split("_")[1])
    
    with get_db_context() as db:
        plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.id == plan_id).first()
        
        if not plan:
            await callback.answer("Тариф не найден", show_alert=True)
            return
        
        await state.update_data(plan_id=plan_id, plan_price=plan.price)
        
        # Show payment methods
        keyboard_buttons = []
        
        # YooKassa
        keyboard_buttons.append([
            InlineKeyboardButton(
                text=f"💳 Банковская карта (ЮKassa) - {plan.price}₽",
                callback_data=f"pay_yookassa_{plan_id}"
            )
        ])
        
        # Telegram Payments (if available)
        telegram_pay = TelegramPayService()
        if telegram_pay.is_available():
            keyboard_buttons.append([
                InlineKeyboardButton(
                    text=f"💎 Telegram Payments - {plan.price}₽",
                    callback_data=f"pay_telegram_{plan_id}"
                )
            ])
        
        keyboard_buttons.append([
            InlineKeyboardButton(text="◀️ Назад", callback_data="buy")
        ])
        
        payment_text = (
            f"💳 Оплата тарифа: {plan.name}\n\n"
            f"📋 Детали:\n"
            f"• Срок: {plan.duration_days} дней\n"
            f"• Трафик: {'Безлимит' if plan.traffic_limit_gb == 0 else f'{plan.traffic_limit_gb} GB'}\n"
            f"• Устройства: до {plan.max_devices}\n"
            f"• Сумма: {plan.price}₽\n\n"
            f"Выберите способ оплаты:"
        )
        
        await callback.message.edit_text(
            payment_text,
            reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard_buttons)
        )
        await state.set_state(PaymentStates.selecting_payment_method)


@router.callback_query(F.data.startswith("pay_yookassa_"))
async def callback_pay_yookassa(callback: CallbackQuery, state: FSMContext):
    """Handle YooKassa payment through abstraction"""
    plan_id = int(callback.data.split("_")[2])
    
    with get_db_context() as db:
        user = db.query(User).filter(User.telegram_id == callback.from_user.id).first()
        plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.id == plan_id).first()
        
        if not user or not plan:
            await callback.answer("Ошибка", show_alert=True)
            return
        
        try:
            # Используем платежную абстракцию
            payment_service = PaymentService()
            payment = payment_service.create_payment(
                provider_type=PaymentProviderType.YOOKASSA.value,
                amount=plan.price,
                currency="RUB",
                description=f"Подписка {plan.name} на {plan.duration_days} дней",
                user_id=user.id,
                metadata={"plan_id": plan_id}
            )
            
            # Save payment to database
            from models import Payment, PaymentMethod, PaymentStatus
            payment_record = Payment(
                user_id=user.id,
                telegram_id=user.telegram_id,
                amount=plan.price,
                currency="RUB",
                payment_method=PaymentMethod.YOOKASSA,
                status=PaymentStatus.PENDING,
                provider_payment_id=payment["payment_id"],
                description=f"Подписка {plan.name}"
            )
            db.add(payment_record)
            db.commit()
            
            # Логируем создание платежа
            logging_service = LoggingService(db)
            logging_service.log_payment(payment_record, "created")
            
            payment_url = payment.get("confirmation_url")
            
            if payment_url:
                await callback.message.edit_text(
                    f"💳 Оплата через ЮKassa\n\n"
                    f"Сумма: {plan.price}₽\n\n"
                    f"Нажмите на кнопку для перехода к оплате:",
                    reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                        [InlineKeyboardButton(text="💳 Оплатить", url=payment_url)],
                        [InlineKeyboardButton(text="◀️ Назад", callback_data="buy")]
                    ])
                )
            else:
                await callback.message.edit_text(
                    f"💳 Платеж создан\n\n"
                    f"Сумма: {plan.price}₽\n\n"
                    f"Ожидайте подтверждения оплаты.",
                    reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                        [InlineKeyboardButton(text="◀️ Назад", callback_data="buy")]
                    ])
                )
            
            await state.update_data(payment_id=payment_record.id, provider_payment_id=payment["payment_id"])
            await state.set_state(PaymentStates.waiting_payment)
        
        except Exception as e:
            logger.error(f"Error creating payment: {e}")
            await callback.answer("Ошибка создания платежа", show_alert=True)


@router.callback_query(F.data.startswith("pay_telegram_"))
async def callback_pay_telegram(callback: CallbackQuery, state: FSMContext):
    """Handle Telegram Payments through abstraction"""
    plan_id = int(callback.data.split("_")[2])
    
    with get_db_context() as db:
        user = db.query(User).filter(User.telegram_id == callback.from_user.id).first()
        plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.id == plan_id).first()
        
        if not user or not plan:
            await callback.answer("Ошибка", show_alert=True)
            return
        
        try:
            # Используем платежную абстракцию
            payment_service = PaymentService()
            
            if PaymentProviderType.TELEGRAM.value not in payment_service.get_available_providers():
                await callback.answer("Telegram Payments недоступен", show_alert=True)
                return
            
            payment = payment_service.create_payment(
                provider_type=PaymentProviderType.TELEGRAM.value,
                amount=plan.price,
                currency="RUB",
                description=f"Подписка {plan.name} на {plan.duration_days} дней",
                user_id=user.id,
                metadata={"plan_id": plan_id}
            )
            
            # Save payment to database
            from models import Payment, PaymentMethod, PaymentStatus
            payment_record = Payment(
                user_id=user.id,
                telegram_id=user.telegram_id,
                amount=plan.price,
                currency="RUB",
                payment_method=PaymentMethod.TELEGRAM,
                status=PaymentStatus.PENDING,
                provider_payment_id=payment["payment_id"],
                description=f"Подписка {plan.name}"
            )
            db.add(payment_record)
            db.commit()
            
            # Логируем
            logging_service = LoggingService(db)
            logging_service.log_payment(payment_record, "created")
            
            # Note: В реальной реализации здесь будет отправка invoice через bot.send_invoice()
            # Используя payment["invoice"] данные
            await callback.answer(
                "Telegram Payments: используйте invoice из payment данных",
                show_alert=True
            )
        
        except Exception as e:
            logger.error(f"Error creating Telegram payment: {e}")
            await callback.answer("Ошибка создания платежа", show_alert=True)


@router.callback_query(F.data == "trial")
async def callback_trial(callback: CallbackQuery):
    """Handle trial access request"""
    with get_db_context() as db:
        user = db.query(User).filter(User.telegram_id == callback.from_user.id).first()
        
        if not user:
            await callback.answer("Пользователь не найден", show_alert=True)
            return
        
        trial_service = TrialService(db)
        
        # Проверяем возможность получения пробного доступа
        if not trial_service.check_trial_eligibility(user):
            await callback.answer(
                "Пробный доступ уже был использован или недоступен",
                show_alert=True
            )
            return
        
        # Выдаем пробный доступ
        try:
            result = trial_service.grant_trial_access(user)
            
            # Логируем
            logging_service = LoggingService(db)
            logging_service.log_user_action(user, "trial_granted", {
                "trial_id": result["trial_id"],
                "duration_days": result["duration_days"],
                "traffic_gb": result["traffic_gb"]
            })
            
            trial_text = (
                f"🎉 Пробный доступ активирован!\n\n"
                f"📅 Действует до: {result['expires_at'].strftime('%d.%m.%Y %H:%M')}\n"
                f"📊 Трафик: {result['traffic_gb']} GB\n"
                f"⏱ Срок: {result['duration_days']} дней\n\n"
                f"Нажмите «Подключиться» для получения ключа доступа."
            )
            
            await callback.message.edit_text(
                trial_text,
                reply_markup=get_user_keyboard(show_trial=False)
            )
            
            await callback.answer("✅ Пробный доступ активирован!")
        
        except Exception as e:
            logger.error(f"Error granting trial access: {e}")
            await callback.answer("Ошибка при выдаче пробного доступа", show_alert=True)


@router.callback_query(F.data == "help")
async def callback_help(callback: CallbackQuery):
    """Handle help button"""
    help_text = (
        f"❓ Помощь по использованию {settings.app_name}\n\n"
        f"📱 Как подключиться:\n"
        f"1. Нажмите кнопку «Подключиться»\n"
        f"2. Скопируйте полученный ключ\n"
        f"3. Установите клиент (например, v2rayNG для Android)\n"
        f"4. Добавьте ключ в клиент\n\n"
        f"💳 Как купить подписку:\n"
        f"1. Нажмите «Купить подписку»\n"
        f"2. Выберите тариф\n"
        f"3. Выберите способ оплаты\n"
        f"4. Оплатите и получите доступ\n\n"
        f"📊 Команды:\n"
        f"/start - Главное меню\n"
        f"/status - Ваш статус\n"
        f"/buy - Купить подписку\n"
        f"/help - Эта справка\n\n"
        f"💬 Поддержка: @your_support_username"
    )
    
    await callback.message.edit_text(
        help_text,
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="◀️ Назад", callback_data="back_to_main")]
        ])
    )


@router.callback_query(F.data == "back_to_main")
async def callback_back_to_main(callback: CallbackQuery, state: FSMContext):
    """Return to main menu"""
    await state.clear()
    await callback.message.edit_text(
        f"👋 Главное меню {settings.app_name}",
        reply_markup=get_user_keyboard()
    )

