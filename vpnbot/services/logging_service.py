"""
Logging Service
Централизованное логирование транзакций и событий
"""
import logging
import json
from datetime import datetime
from typing import Optional, Dict, Any
from sqlalchemy.orm import Session

from models import SystemLog, Payment, User

logger = logging.getLogger(__name__)


class LoggingService:
    """Сервис для логирования событий системы"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def log_payment(
        self,
        payment: Payment,
        action: str,
        metadata: Optional[Dict] = None
    ):
        """Логировать платеж"""
        log = SystemLog(
            log_type="payment",
            level="INFO",
            message=f"Payment {action}: {payment.payment_id} - {payment.amount} {payment.currency}",
            user_id=payment.user_id,
            metadata=json.dumps({
                "payment_id": payment.id,
                "payment_method": payment.payment_method.value,
                "status": payment.status.value,
                "amount": payment.amount,
                "currency": payment.currency,
                **(metadata or {})
            })
        )
        self.db.add(log)
        self.db.commit()
        
        # Также логируем в файл
        logger.info(f"Payment {action}: {payment.payment_id} - User {payment.user_id} - {payment.amount} {payment.currency}")
    
    def log_api_request(
        self,
        endpoint: str,
        method: str,
        user_id: Optional[int] = None,
        status_code: int = 200,
        metadata: Optional[Dict] = None
    ):
        """Логировать API запрос"""
        level = "ERROR" if status_code >= 400 else "INFO"
        
        log = SystemLog(
            log_type="api",
            level=level,
            message=f"API {method} {endpoint} - {status_code}",
            user_id=user_id,
            metadata=json.dumps({
                "endpoint": endpoint,
                "method": method,
                "status_code": status_code,
                **(metadata or {})
            })
        )
        self.db.add(log)
        self.db.commit()
    
    def log_user_action(
        self,
        user: User,
        action: str,
        metadata: Optional[Dict] = None
    ):
        """Логировать действие пользователя"""
        log = SystemLog(
            log_type="user",
            level="INFO",
            message=f"User {action}: {user.telegram_id}",
            user_id=user.id,
            metadata=json.dumps({
                "telegram_id": user.telegram_id,
                "username": user.username,
                "action": action,
                **(metadata or {})
            })
        )
        self.db.add(log)
        self.db.commit()
    
    def log_node_event(
        self,
        node_id: str,
        event: str,
        metadata: Optional[Dict] = None
    ):
        """Логировать событие ноды"""
        log = SystemLog(
            log_type="node",
            level="INFO",
            message=f"Node {event}: {node_id}",
            metadata=json.dumps({
                "node_id": node_id,
                "event": event,
                **(metadata or {})
            })
        )
        self.db.add(log)
        self.db.commit()
    
    def log_error(
        self,
        error_type: str,
        message: str,
        user_id: Optional[int] = None,
        metadata: Optional[Dict] = None
    ):
        """Логировать ошибку"""
        log = SystemLog(
            log_type=error_type,
            level="ERROR",
            message=message,
            user_id=user_id,
            metadata=json.dumps(metadata or {})
        )
        self.db.add(log)
        self.db.commit()
        
        # Также логируем в файл
        logger.error(f"{error_type}: {message} - User {user_id}")
    
    def get_logs(
        self,
        log_type: Optional[str] = None,
        user_id: Optional[int] = None,
        limit: int = 100
    ) -> list:
        """Получить логи"""
        query = self.db.query(SystemLog)
        
        if log_type:
            query = query.filter(SystemLog.log_type == log_type)
        
        if user_id:
            query = query.filter(SystemLog.user_id == user_id)
        
        return query.order_by(SystemLog.created_at.desc()).limit(limit).all()

