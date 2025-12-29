"""
Telegram Payments integration
"""
import logging
from typing import Dict, Optional
from datetime import datetime

from config import settings

logger = logging.getLogger(__name__)


class TelegramPayService:
    """Service for Telegram Payments"""
    
    def __init__(self):
        self.provider_token = settings.telegram_payment_provider_token
        if not self.provider_token:
            logger.warning("Telegram Payment provider token not configured")
    
    def create_invoice(
        self,
        title: str,
        description: str,
        payload: str,
        amount: int,  # in kopecks
        currency: str = "RUB"
    ) -> Dict:
        """Create invoice for Telegram Payments"""
        if not self.provider_token:
            raise ValueError("Telegram Payment provider token not configured")
        
        return {
            "title": title,
            "description": description,
            "payload": payload,
            "provider_token": self.provider_token,
            "currency": currency,
            "prices": [
                {
                    "label": title,
                    "amount": amount
                }
            ]
        }
    
    def is_available(self) -> bool:
        """Check if Telegram Payments is available"""
        return bool(self.provider_token)

