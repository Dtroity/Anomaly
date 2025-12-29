"""
FastAPI application for Anomaly VPN Bot
"""
import logging
from datetime import datetime, timedelta
from typing import Optional

from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from database import get_db
from models import User, Payment, PaymentStatus, PaymentMethod, UserRole
from services.payment_provider import PaymentService, PaymentProviderType
from services.marzban import MarzbanService
from services.nodes import NodeService
from services.logging_service import LoggingService
from config import settings

logger = logging.getLogger(__name__)

app = FastAPI(title=f"{settings.app_name} API", version="1.0.0")

# Import payment service
from services.payment_provider import PaymentService
payment_service = PaymentService()


class PaymentWebhook(BaseModel):
    """YooKassa webhook model"""
    event: str
    object: dict


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": settings.app_name,
        "version": "1.0.0",
        "status": "running"
    }


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}


@app.post("/webhook/yookassa")
async def yookassa_webhook(
    webhook: PaymentWebhook,
    x_shop_id: Optional[str] = Header(None),
    x_shop_signature: Optional[str] = Header(None)
):
    """Handle YooKassa webhook"""
    try:
        if webhook.event == "payment.succeeded":
            payment_id = webhook.object.get("id")
            
            if not payment_id:
                raise HTTPException(status_code=400, detail="Payment ID missing")
            
            # Используем платежную абстракцию
            payment_service = PaymentService()
            
            # Find payment in database
            with get_db() as db:
                payment = db.query(Payment).filter(
                    Payment.provider_payment_id == payment_id
                ).first()
                
                if not payment:
                    logger.warning(f"Payment {payment_id} not found in database")
                    return JSONResponse({"status": "ok"})
                
                # Проверяем статус через провайдера
                payment_status = payment_service.get_payment_status(
                    PaymentProviderType.YOOKASSA.value,
                    payment_id
                )
                
                # Update payment status
                if payment_status == PaymentStatus.SUCCESS:
                    payment.status = PaymentStatus.SUCCESS
                    payment.completed_at = datetime.utcnow()
                    
                    # Update user subscription
                    user = db.query(User).filter(User.id == payment.user_id).first()
                    if user:
                        # Get plan from payment metadata or use defaults
                        from models import SubscriptionPlan
                        # For simplicity, using default values
                        # In production, store plan_id in payment metadata
                        
                        user.role = UserRole.USER
                        user.expires_at = datetime.utcnow() + timedelta(days=30)  # Default
                        user.traffic_limit_gb = settings.default_traffic_limit_gb
                        user.source = "paid"
                        
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
                    
                    # Логируем успешный платеж
                    logging_service = LoggingService(db)
                    logging_service.log_payment(payment, "completed")
                    
                    db.commit()
        
        return JSONResponse({"status": "ok"})
    
    except Exception as e:
        logger.error(f"Error processing YooKassa webhook: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/payment/check/{payment_id}")
async def check_payment(payment_id: str):
    """Check payment status"""
    try:
        with get_db() as db:
            payment = db.query(Payment).filter(
                Payment.provider_payment_id == payment_id
            ).first()
            
            if not payment:
                raise HTTPException(status_code=404, detail="Payment not found")
            
            # Используем платежную абстракцию
            payment_status = payment_service.get_payment_status(
                payment.payment_method.value,
                payment_id
            )
            
            return {
                "payment_id": payment_id,
                "status": payment_status.value,
                "amount": payment.amount,
                "currency": payment.currency
            }
    
    except Exception as e:
        logger.error(f"Error checking payment: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/payment/providers")
async def get_payment_providers():
    """Получить список доступных платежных провайдеров"""
    return {
        "providers": payment_service.get_available_providers()
    }


@app.get("/user/{telegram_id}")
async def get_user_info(telegram_id: int, api_key: str = Header(None)):
    """Get user information (protected endpoint)"""
    if api_key != settings.api_secret_key:
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    try:
        with get_db() as db:
            user = db.query(User).filter(User.telegram_id == telegram_id).first()
            
            if not user:
                raise HTTPException(status_code=404, detail="User not found")
            
            return {
                "telegram_id": user.telegram_id,
                "username": user.username,
                "role": user.role.value,
                "expires_at": user.expires_at.isoformat() if user.expires_at else None,
                "traffic_limit_gb": user.traffic_limit_gb,
                "used_traffic_gb": user.used_traffic_gb,
                "is_expired": user.is_expired,
                "is_traffic_exceeded": user.is_traffic_exceeded
            }
    
    except Exception as e:
        logger.error(f"Error getting user info: {e}")
        raise HTTPException(status_code=500, detail=str(e))

