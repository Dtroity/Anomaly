"""
YooKassa payment integration
"""
import logging
from typing import Dict, Optional
from datetime import datetime
import yookassa
from yookassa import Payment, Configuration

from config import settings

logger = logging.getLogger(__name__)


class YooKassaService:
    """Service for YooKassa payments"""
    
    def __init__(self):
        Configuration.account_id = settings.yookassa_shop_id
        Configuration.secret_key = settings.yookassa_secret_key
        self.test_mode = settings.yookassa_test_mode
    
    def create_payment(
        self,
        amount: float,
        currency: str = "RUB",
        description: str = "Оплата подписки",
        user_id: int = None,
        telegram_id: int = None,
        return_url: Optional[str] = None
    ) -> Dict:
        """Create payment in YooKassa"""
        try:
            payment_data = {
                "amount": {
                    "value": f"{amount:.2f}",
                    "currency": currency
                },
                "confirmation": {
                    "type": "redirect",
                    "return_url": return_url or f"{settings.app_url}/payment/success"
                },
                "capture": True,
                "description": description,
                "metadata": {
                    "user_id": str(user_id) if user_id else "",
                    "telegram_id": str(telegram_id) if telegram_id else ""
                }
            }
            
            payment = Payment.create(payment_data, idempotency_key=f"{telegram_id}_{int(datetime.utcnow().timestamp())}")
            
            return {
                "payment_id": payment.id,
                "status": payment.status,
                "confirmation_url": payment.confirmation.confirmation_url if payment.confirmation else None,
                "amount": float(payment.amount.value),
                "currency": payment.amount.currency
            }
        except Exception as e:
            logger.error(f"Error creating YooKassa payment: {e}")
            raise
    
    def get_payment(self, payment_id: str) -> Optional[Dict]:
        """Get payment status from YooKassa"""
        try:
            payment = Payment.find_one(payment_id)
            return {
                "payment_id": payment.id,
                "status": payment.status,
                "amount": float(payment.amount.value),
                "currency": payment.amount.currency,
                "paid": payment.paid,
                "metadata": payment.metadata
            }
        except Exception as e:
            logger.error(f"Error getting YooKassa payment {payment_id}: {e}")
            return None
    
    def is_payment_successful(self, payment_id: str) -> bool:
        """Check if payment is successful"""
        payment_info = self.get_payment(payment_id)
        if not payment_info:
            return False
        return payment_info.get("status") == "succeeded" and payment_info.get("paid", False)

