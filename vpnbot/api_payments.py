"""
Payment API endpoints with abstraction layer
Функции для интеграции в основной api.py
"""
import logging
from datetime import datetime, timedelta
from typing import Optional, Dict

from fastapi import HTTPException, Header, Request
from fastapi.responses import JSONResponse

from database import get_db
from models import User, Payment, PaymentStatus, PaymentMethod, UserRole
from services.payment_provider import PaymentService, PaymentProviderType
from services.marzban import MarzbanService
from services.nodes import NodeService
from services.logging_service import LoggingService
from config import settings

logger = logging.getLogger(__name__)

# Payment service instance
payment_service = PaymentService()


async def payment_webhook(
    provider: str,
    request: Request
):
    """Универсальный webhook для всех платежных провайдеров"""
    try:
        # Получаем данные из запроса
        body = await request.json()
        
        # Получаем подпись из заголовков
        signature = request.headers.get("X-Signature") or request.headers.get("X-Shop-Signature")
        
        # Обрабатываем webhook через абстракцию
        result = payment_service.process_webhook(provider, body, signature)
        
        if result.get("status") == PaymentStatus.SUCCESS.value:
            # Находим платеж в БД
            with get_db() as db:
                payment = db.query(Payment).filter(
                    Payment.provider_payment_id == result.get("payment_id")
                ).first()
                
                if payment:
                    # Обновляем статус платежа
                    payment.status = PaymentStatus.SUCCESS
                    payment.completed_at = datetime.utcnow()
                    
                    # Обновляем пользователя
                    user = db.query(User).filter(User.id == payment.user_id).first()
                    if user:
                        user.role = UserRole.USER
                        user.expires_at = datetime.utcnow() + timedelta(days=30)
                        user.traffic_limit_gb = settings.default_traffic_limit_gb
                        user.source = "paid"
                        
                        # Обновляем в Marzban
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
                                data_limit = int(user.traffic_limit_gb * 1024 * 1024 * 1024) if user.traffic_limit_gb > 0 else None
                                
                                existing_user = marzban.get_user_sync(username)
                                if existing_user:
                                    marzban.update_user_sync(
                                        username=username,
                                        data_limit=data_limit,
                                        expire_date=expire_date
                                    )
                                else:
                                    marzban.create_user_sync(
                                        username=username,
                                        data_limit=data_limit,
                                        expire_date=expire_date
                                    )
                                
                                user.node_assigned = node["id"]
                        except Exception as e:
                            logger.error(f"Error updating Marzban user: {e}")
                    
                    # Логируем платеж
                    logging_service = LoggingService(db)
                    logging_service.log_payment(payment, "completed")
                    
                    db.commit()
        
        return JSONResponse({"status": "ok"})
    
    except Exception as e:
        logger.error(f"Error processing payment webhook: {e}")
        return JSONResponse({"status": "error", "message": str(e)}, status_code=500)




async def create_payment(
    provider: str,
    amount: float,
    currency: str,
    description: str,
    user_id: int,
    api_key: str = Header(None)
):
    """Создать платеж через указанного провайдера"""
    if api_key != settings.api_secret_key:
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    try:
        # Создаем платеж через абстракцию
        payment_data = payment_service.create_payment(
            provider_type=provider,
            amount=amount,
            currency=currency,
            description=description,
            user_id=user_id
        )
        
        # Сохраняем в БД
        with get_db() as db:
            user = db.query(User).filter(User.id == user_id).first()
            if not user:
                raise HTTPException(status_code=404, detail="User not found")
            
            payment = Payment(
                user_id=user_id,
                telegram_id=user.telegram_id,
                amount=amount,
                currency=currency,
                payment_method=PaymentMethod(provider),
                status=PaymentStatus.PENDING,
                provider_payment_id=payment_data.get("payment_id"),
                description=description
            )
            db.add(payment)
            db.commit()
            
            # Логируем
            logging_service = LoggingService(db)
            logging_service.log_payment(payment, "created")
        
        return payment_data
    
    except Exception as e:
        logger.error(f"Error creating payment: {e}")
        raise HTTPException(status_code=500, detail=str(e))


async def get_payment_providers():
    """Получить список доступных платежных провайдеров"""
    return {
        "providers": payment_service.get_available_providers()
    }

