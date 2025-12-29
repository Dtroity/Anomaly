"""
Trial/Free Access Service
Управление пробным и бесплатным доступом
"""
import logging
from datetime import datetime, timedelta
from typing import Optional, Dict
from sqlalchemy.orm import Session

from models import User, UserRole, TrialAccess, UserSession
from services.marzban import MarzbanService
from services.nodes import NodeService
from config import settings

logger = logging.getLogger(__name__)


class TrialService:
    """Сервис для управления пробным доступом"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def grant_trial_access(
        self,
        user: User,
        duration_days: Optional[int] = None,
        traffic_gb: Optional[float] = None,
        source: str = "trial"
    ) -> Dict:
        """Выдать пробный доступ пользователю"""
        # Используем настройки по умолчанию, если не указаны
        duration_days = duration_days or settings.free_trial_days
        traffic_gb = traffic_gb or settings.free_trial_traffic_gb
        
        expires_at = datetime.utcnow() + timedelta(days=duration_days)
        
        # Создаем запись о пробном доступе
        trial = TrialAccess(
            user_id=user.id,
            telegram_id=user.telegram_id,
            duration_days=duration_days,
            traffic_limit_gb=traffic_gb,
            started_at=datetime.utcnow(),
            expires_at=expires_at,
            source=source
        )
        self.db.add(trial)
        
        # Обновляем пользователя
        user.role = UserRole.USER
        user.expires_at = expires_at
        user.traffic_limit_gb = traffic_gb
        user.used_traffic_gb = 0.0
        user.source = source
        
        # Создаем/обновляем пользователя в Marzban
        try:
            node_service = NodeService(self.db)
            node = node_service.select_best_node()
            
            if node:
                marzban = MarzbanService(
                    api_url=node["url"],
                    username=node["username"],
                    password=node["password"]
                )
                
                username = f"user_{user.telegram_id}"
                expire_date = expires_at
                data_limit = int(traffic_gb * 1024 * 1024 * 1024) if traffic_gb > 0 else None
                
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
            logger.error(f"Error creating Marzban user for trial: {e}")
        
        self.db.commit()
        self.db.refresh(trial)
        
        return {
            "success": True,
            "trial_id": trial.id,
            "expires_at": expires_at,
            "traffic_gb": traffic_gb,
            "duration_days": duration_days
        }
    
    def check_trial_eligibility(self, user: User) -> bool:
        """Проверить, может ли пользователь получить пробный доступ"""
        # Проверяем, есть ли уже активный пробный доступ
        active_trial = self.db.query(TrialAccess).filter(
            TrialAccess.telegram_id == user.telegram_id,
            TrialAccess.is_active == True,
            TrialAccess.expires_at > datetime.utcnow()
        ).first()
        
        if active_trial:
            return False
        
        # Проверяем, был ли уже пробный доступ
        previous_trial = self.db.query(TrialAccess).filter(
            TrialAccess.telegram_id == user.telegram_id
        ).first()
        
        # Если был пробный доступ, проверяем, можно ли выдать еще раз
        # (можно настроить логику: один раз навсегда или периодически)
        if previous_trial:
            # Для начала: один пробный доступ на пользователя
            return False
        
        return True
    
    def get_active_trial(self, user: User) -> Optional[TrialAccess]:
        """Получить активный пробный доступ пользователя"""
        return self.db.query(TrialAccess).filter(
            TrialAccess.telegram_id == user.telegram_id,
            TrialAccess.is_active == True,
            TrialAccess.expires_at > datetime.utcnow()
        ).first()
    
    def expire_trial(self, trial: TrialAccess):
        """Истечение пробного доступа"""
        trial.is_active = False
        
        # Обновляем пользователя
        user = self.db.query(User).filter(User.id == trial.user_id).first()
        if user and user.source in ["trial", "free"]:
            # Можно оставить доступ, но с ограничениями, или отключить
            # Пока отключаем
            user.is_active = False
        
        self.db.commit()

