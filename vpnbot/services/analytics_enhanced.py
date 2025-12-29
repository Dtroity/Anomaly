"""
Enhanced Analytics Service
Расширенная аналитика с метриками нагрузки нод, оттока и сессий
"""
import logging
from datetime import datetime, timedelta
from typing import Dict, List
from sqlalchemy import func, and_, or_
from sqlalchemy.orm import Session

from models import (
    User, Payment, UserRole, PaymentStatus, 
    TrialAccess, SystemLog, UserSession, Node
)

logger = logging.getLogger(__name__)


class EnhancedAnalyticsService:
    """Расширенный сервис аналитики"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def get_active_users_count(self) -> int:
        """Активные пользователи (не истекшие, не забаненные)"""
        now = datetime.utcnow()
        return self.db.query(User).filter(
            and_(
                User.role != UserRole.BANNED,
                User.is_active == True,
                or_(
                    User.expires_at.is_(None),
                    User.expires_at > now
                )
            )
        ).count()
    
    def get_active_subscriptions_count(self) -> int:
        """Активные платные подписки"""
        now = datetime.utcnow()
        return self.db.query(User).filter(
            and_(
                User.role == UserRole.USER,
                User.is_active == True,
                User.expires_at > now,
                User.source == "paid"
            )
        ).count()
    
    def get_trial_users_count(self) -> int:
        """Пользователи на пробном доступе"""
        now = datetime.utcnow()
        return self.db.query(TrialAccess).filter(
            and_(
                TrialAccess.is_active == True,
                TrialAccess.expires_at > now
            )
        ).count()
    
    def get_revenue(self, days: int = 30) -> float:
        """Доход за период"""
        since = datetime.utcnow() - timedelta(days=days)
        result = self.db.query(func.sum(Payment.amount)).filter(
            and_(
                Payment.status == PaymentStatus.SUCCESS,
                Payment.completed_at >= since
            )
        ).scalar()
        return float(result) if result else 0.0
    
    def get_revenue_by_provider(self, days: int = 30) -> Dict[str, float]:
        """Доход по провайдерам"""
        since = datetime.utcnow() - timedelta(days=days)
        payments = self.db.query(
            Payment.payment_method,
            func.sum(Payment.amount)
        ).filter(
            and_(
                Payment.status == PaymentStatus.SUCCESS,
                Payment.completed_at >= since
            )
        ).group_by(Payment.payment_method).all()
        
        return {method.value: float(amount) for method, amount in payments}
    
    def get_node_load_stats(self) -> List[Dict]:
        """Статистика нагрузки по нодам"""
        nodes = self.db.query(Node).filter(Node.is_active == True).all()
        
        stats = []
        for node in nodes:
            # Подсчет пользователей на ноде
            users_on_node = self.db.query(User).filter(
                User.node_assigned == node.node_id,
                User.is_active == True
            ).count()
            
            load_percent = 0.0
            if node.max_users > 0:
                load_percent = (users_on_node / node.max_users) * 100
            
            stats.append({
                "node_id": node.node_id,
                "name": node.name,
                "current_users": users_on_node,
                "max_users": node.max_users,
                "load_percent": round(load_percent, 2),
                "is_active": node.is_active
            })
        
        return stats
    
    def get_churn_rate(self, days: int = 30) -> float:
        """Процент оттока пользователей"""
        since = datetime.utcnow() - timedelta(days=days)
        
        # Пользователи, которые были активны, но теперь неактивны
        total_active_before = self.db.query(User).filter(
            User.created_at < since,
            User.is_active == True
        ).count()
        
        inactive_now = self.db.query(User).filter(
            and_(
                User.created_at < since,
                User.is_active == False
            )
        ).count()
        
        if total_active_before == 0:
            return 0.0
        
        return (inactive_now / total_active_before) * 100
    
    def get_average_session_duration(self, days: int = 30) -> float:
        """Средняя длительность сессии"""
        since = datetime.utcnow() - timedelta(days=days)
        
        sessions = self.db.query(UserSession).filter(
            and_(
                UserSession.session_start >= since,
                UserSession.duration_seconds.isnot(None)
            )
        ).all()
        
        if not sessions:
            return 0.0
        
        total_duration = sum(s.duration_seconds for s in sessions)
        return total_duration / len(sessions)
    
    def get_conversion_rate(self, days: int = 30) -> float:
        """Процент конверсии (trial -> paid)"""
        since = datetime.utcnow() - timedelta(days=days)
        
        # Пользователи, которые начали с trial
        trial_users = self.db.query(TrialAccess).filter(
            TrialAccess.started_at >= since
        ).count()
        
        # Пользователи, которые перешли на платную подписку
        converted = self.db.query(User).filter(
            and_(
                User.source == "paid",
                User.created_at >= since
            )
        ).count()
        
        if trial_users == 0:
            return 0.0
        
        return (converted / trial_users) * 100
    
    def get_dashboard_stats(self) -> Dict:
        """Комплексная статистика для дашборда"""
        now = datetime.utcnow()
        
        # Активные пользователи
        active_users = self.get_active_users_count()
        
        # Активные платные подписки
        active_paid = self.get_active_subscriptions_count()
        
        # Пробные доступы
        trial_users = self.get_trial_users_count()
        
        # Всего пользователей
        total_users = self.db.query(User).count()
        
        # Доход
        revenue_30d = self.get_revenue(30)
        revenue_today = self.get_revenue(1)
        revenue_by_provider = self.get_revenue_by_provider(30)
        
        # Нагрузка нод
        node_stats = self.get_node_load_stats()
        
        # Метрики
        churn_rate = self.get_churn_rate(30)
        avg_session = self.get_average_session_duration(30)
        conversion_rate = self.get_conversion_rate(30)
        
        # Платежи за сегодня
        today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        payments_today = self.db.query(Payment).filter(
            and_(
                Payment.status == PaymentStatus.SUCCESS,
                Payment.completed_at >= today
            )
        ).count()
        
        return {
            "active_users": active_users,
            "active_paid_subscriptions": active_paid,
            "trial_users": trial_users,
            "total_users": total_users,
            "revenue_30d": revenue_30d,
            "revenue_today": revenue_today,
            "revenue_by_provider": revenue_by_provider,
            "payments_today": payments_today,
            "node_stats": node_stats,
            "churn_rate": round(churn_rate, 2),
            "avg_session_duration_seconds": round(avg_session, 0),
            "conversion_rate": round(conversion_rate, 2),
            "users_by_role": self._get_users_by_role(),
            "recent_payments": self._get_recent_payments(10)
        }
    
    def _get_users_by_role(self) -> Dict[str, int]:
        """Пользователи по ролям"""
        roles = {}
        for role in UserRole:
            count = self.db.query(User).filter(User.role == role).count()
            roles[role.value] = count
        return roles
    
    def _get_recent_payments(self, limit: int = 10) -> List[Dict]:
        """Последние платежи"""
        payments = self.db.query(Payment).filter(
            Payment.status == PaymentStatus.SUCCESS
        ).order_by(Payment.completed_at.desc()).limit(limit).all()
        
        return [
            {
                "id": p.id,
                "user_id": p.user_id,
                "telegram_id": p.telegram_id,
                "amount": p.amount,
                "currency": p.currency,
                "method": p.payment_method.value,
                "completed_at": p.completed_at.isoformat() if p.completed_at else None
            }
            for p in payments
        ]

