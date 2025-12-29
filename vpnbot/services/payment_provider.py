"""
Payment Provider Abstraction Layer
Абстракция для работы с различными платежными системами
"""
import logging
from abc import ABC, abstractmethod
from typing import Dict, Optional
from datetime import datetime
from enum import Enum

logger = logging.getLogger(__name__)


class PaymentProviderType(str, Enum):
    """Типы платежных провайдеров"""
    YOOKASSA = "yookassa"
    TELEGRAM = "telegram"
    CRYPTO = "crypto"
    MANUAL = "manual"


class PaymentStatus(str, Enum):
    """Статусы платежей"""
    PENDING = "pending"
    PROCESSING = "processing"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"
    REFUNDED = "refunded"


class PaymentProvider(ABC):
    """Абстрактный класс для платежных провайдеров"""
    
    @abstractmethod
    def create_payment(
        self,
        amount: float,
        currency: str,
        description: str,
        user_id: int,
        metadata: Optional[Dict] = None
    ) -> Dict:
        """Создать платеж"""
        pass
    
    @abstractmethod
    def get_payment_status(self, payment_id: str) -> PaymentStatus:
        """Получить статус платежа"""
        pass
    
    @abstractmethod
    def verify_webhook(self, data: Dict, signature: Optional[str] = None) -> bool:
        """Проверить webhook от провайдера"""
        pass
    
    @abstractmethod
    def process_webhook(self, data: Dict) -> Dict:
        """Обработать webhook от провайдера"""
        pass


class YooKassaProvider(PaymentProvider):
    """Провайдер ЮKassa"""
    
    def __init__(self, shop_id: str, secret_key: str, test_mode: bool = False):
        self.shop_id = shop_id
        self.secret_key = secret_key
        self.test_mode = test_mode
        self._init_client()
    
    def _init_client(self):
        """Инициализация клиента ЮKassa"""
        try:
            import yookassa
            from yookassa import Configuration
            Configuration.account_id = self.shop_id
            Configuration.secret_key = self.secret_key
        except ImportError:
            logger.error("yookassa library not installed")
    
    def create_payment(
        self,
        amount: float,
        currency: str,
        description: str,
        user_id: int,
        metadata: Optional[Dict] = None
    ) -> Dict:
        """Создать платеж в ЮKassa"""
        try:
            from yookassa import Payment
            from config import settings
            
            payment_data = {
                "amount": {
                    "value": f"{amount:.2f}",
                    "currency": currency
                },
                "confirmation": {
                    "type": "redirect",
                    "return_url": f"{settings.app_url}/payment/success"
                },
                "capture": True,
                "description": description,
                "metadata": {
                    "user_id": str(user_id),
                    **(metadata or {})
                }
            }
            
            payment = Payment.create(
                payment_data,
                idempotency_key=f"{user_id}_{int(datetime.utcnow().timestamp())}"
            )
            
            return {
                "provider": PaymentProviderType.YOOKASSA.value,
                "payment_id": payment.id,
                "status": payment.status,
                "confirmation_url": payment.confirmation.confirmation_url if payment.confirmation else None,
                "amount": float(payment.amount.value),
                "currency": payment.amount.currency
            }
        except Exception as e:
            logger.error(f"Error creating YooKassa payment: {e}")
            raise
    
    def get_payment_status(self, payment_id: str) -> PaymentStatus:
        """Получить статус платежа"""
        try:
            from yookassa import Payment
            payment = Payment.find_one(payment_id)
            
            if payment.status == "succeeded" and payment.paid:
                return PaymentStatus.SUCCESS
            elif payment.status == "canceled":
                return PaymentStatus.CANCELLED
            elif payment.status == "pending":
                return PaymentStatus.PENDING
            else:
                return PaymentStatus.FAILED
        except Exception as e:
            logger.error(f"Error getting YooKassa payment status: {e}")
            return PaymentStatus.FAILED
    
    def verify_webhook(self, data: Dict, signature: Optional[str] = None) -> bool:
        """Проверить webhook от ЮKassa"""
        # ЮKassa использует IP whitelist и подпись в заголовках
        # В продакшене нужно проверять подпись
        return True
    
    def process_webhook(self, data: Dict) -> Dict:
        """Обработать webhook от ЮKassa"""
        event = data.get("event")
        payment_obj = data.get("object", {})
        
        if event == "payment.succeeded":
            return {
                "payment_id": payment_obj.get("id"),
                "status": PaymentStatus.SUCCESS.value,
                "amount": float(payment_obj.get("amount", {}).get("value", 0)),
                "currency": payment_obj.get("amount", {}).get("currency", "RUB"),
                "metadata": payment_obj.get("metadata", {})
            }
        
        return {
            "payment_id": payment_obj.get("id"),
            "status": PaymentStatus.PENDING.value
        }


class TelegramPayProvider(PaymentProvider):
    """Провайдер Telegram Payments"""
    
    def __init__(self, provider_token: str):
        self.provider_token = provider_token
    
    def create_payment(
        self,
        amount: float,
        currency: str,
        description: str,
        user_id: int,
        metadata: Optional[Dict] = None
    ) -> Dict:
        """Создать платеж через Telegram Payments"""
        return {
            "provider": PaymentProviderType.TELEGRAM.value,
            "payment_id": f"tg_{user_id}_{int(datetime.utcnow().timestamp())}",
            "status": PaymentStatus.PENDING.value,
            "amount": amount,
            "currency": currency,
            "invoice": {
                "title": description,
                "description": description,
                "payload": f"user_{user_id}",
                "provider_token": self.provider_token,
                "currency": currency,
                "prices": [{"label": description, "amount": int(amount * 100)}]
            }
        }
    
    def get_payment_status(self, payment_id: str) -> PaymentStatus:
        """Получить статус платежа"""
        # Telegram Payments обрабатывается через бота
        return PaymentStatus.PENDING
    
    def verify_webhook(self, data: Dict, signature: Optional[str] = None) -> bool:
        """Проверить webhook"""
        return True
    
    def process_webhook(self, data: Dict) -> Dict:
        """Обработать webhook"""
        return {
            "payment_id": data.get("payment_id"),
            "status": PaymentStatus.SUCCESS.value if data.get("success") else PaymentStatus.FAILED.value
        }


class CryptoProvider(PaymentProvider):
    """Провайдер криптоплатежей"""
    
    def __init__(self, wallet_address: str, network: str = "TRC20"):
        self.wallet_address = wallet_address
        self.network = network
    
    def create_payment(
        self,
        amount: float,
        currency: str,
        description: str,
        user_id: int,
        metadata: Optional[Dict] = None
    ) -> Dict:
        """Создать платеж через крипту"""
        payment_id = f"crypto_{user_id}_{int(datetime.utcnow().timestamp())}"
        
        return {
            "provider": PaymentProviderType.CRYPTO.value,
            "payment_id": payment_id,
            "status": PaymentStatus.PENDING.value,
            "amount": amount,
            "currency": currency,
            "wallet_address": self.wallet_address,
            "network": self.network,
            "payment_address": self._generate_payment_address(payment_id, amount)
        }
    
    def _generate_payment_address(self, payment_id: str, amount: float) -> str:
        """Генерация адреса для оплаты (заглушка)"""
        # В реальной реализации здесь будет интеграция с крипто-кошельком
        return self.wallet_address
    
    def get_payment_status(self, payment_id: str) -> PaymentStatus:
        """Проверить статус крипто-платежа"""
        # В реальной реализации здесь будет проверка блокчейна
        return PaymentStatus.PENDING
    
    def verify_webhook(self, data: Dict, signature: Optional[str] = None) -> bool:
        """Проверить webhook"""
        return True
    
    def process_webhook(self, data: Dict) -> Dict:
        """Обработать webhook от крипто-сервиса"""
        return {
            "payment_id": data.get("payment_id"),
            "status": PaymentStatus.SUCCESS.value if data.get("confirmed") else PaymentStatus.PENDING.value,
            "tx_hash": data.get("tx_hash"),
            "amount": data.get("amount")
        }


class PaymentService:
    """Сервис для работы с платежами через абстракцию"""
    
    def __init__(self):
        self.providers: Dict[str, PaymentProvider] = {}
        self._init_providers()
    
    def _init_providers(self):
        """Инициализация провайдеров"""
        from config import settings
        
        # ЮKassa
        if settings.yookassa_shop_id and settings.yookassa_secret_key:
            self.providers[PaymentProviderType.YOOKASSA.value] = YooKassaProvider(
                shop_id=settings.yookassa_shop_id,
                secret_key=settings.yookassa_secret_key,
                test_mode=settings.yookassa_test_mode
            )
        
        # Telegram Payments
        if settings.telegram_payment_provider_token:
            self.providers[PaymentProviderType.TELEGRAM.value] = TelegramPayProvider(
                provider_token=settings.telegram_payment_provider_token
            )
        
        # Crypto (опционально)
        # if settings.crypto_wallet_address:
        #     self.providers[PaymentProviderType.CRYPTO.value] = CryptoProvider(
        #         wallet_address=settings.crypto_wallet_address,
        #         network=settings.crypto_network
        #     )
    
    def create_payment(
        self,
        provider_type: str,
        amount: float,
        currency: str,
        description: str,
        user_id: int,
        metadata: Optional[Dict] = None
    ) -> Dict:
        """Создать платеж через указанного провайдера"""
        if provider_type not in self.providers:
            raise ValueError(f"Provider {provider_type} not available")
        
        provider = self.providers[provider_type]
        return provider.create_payment(amount, currency, description, user_id, metadata)
    
    def get_payment_status(self, provider_type: str, payment_id: str) -> PaymentStatus:
        """Получить статус платежа"""
        if provider_type not in self.providers:
            raise ValueError(f"Provider {provider_type} not available")
        
        provider = self.providers[provider_type]
        return provider.get_payment_status(payment_id)
    
    def process_webhook(self, provider_type: str, data: Dict, signature: Optional[str] = None) -> Dict:
        """Обработать webhook от провайдера"""
        if provider_type not in self.providers:
            raise ValueError(f"Provider {provider_type} not available")
        
        provider = self.providers[provider_type]
        
        if not provider.verify_webhook(data, signature):
            raise ValueError("Invalid webhook signature")
        
        return provider.process_webhook(data)
    
    def get_available_providers(self) -> list:
        """Получить список доступных провайдеров"""
        return list(self.providers.keys())

