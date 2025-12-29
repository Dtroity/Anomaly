"""
Analytics service
"""
import logging
from datetime import datetime, timedelta
from typing import Dict, List
from sqlalchemy import func, and_, or_
from sqlalchemy.orm import Session

from models import User, Payment, UserRole, PaymentStatus

logger = logging.getLogger(__name__)


class AnalyticsService:
    """Service for analytics and statistics"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def get_active_users_count(self) -> int:
        """Get count of active users (not expired, not banned)"""
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
        """Get count of active paid subscriptions"""
        now = datetime.utcnow()
        return self.db.query(User).filter(
            and_(
                User.role == UserRole.USER,
                User.is_active == True,
                User.expires_at > now,
                User.source == "paid"
            )
        ).count()
    
    def get_promo_issued_count(self, days: int = 30) -> int:
        """Get count of promo codes issued in last N days"""
        since = datetime.utcnow() - timedelta(days=days)
        return self.db.query(User).filter(
            and_(
                User.role == UserRole.PROMO,
                User.created_at >= since
            )
        ).count()
    
    def get_revenue(self, days: int = 30) -> float:
        """Get total revenue for last N days"""
        since = datetime.utcnow() - timedelta(days=days)
        result = self.db.query(func.sum(Payment.amount)).filter(
            and_(
                Payment.status == PaymentStatus.SUCCESS,
                Payment.completed_at >= since
            )
        ).scalar()
        return float(result) if result else 0.0
    
    def get_revenue_today(self) -> float:
        """Get revenue for today"""
        today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        result = self.db.query(func.sum(Payment.amount)).filter(
            and_(
                Payment.status == PaymentStatus.SUCCESS,
                Payment.completed_at >= today
            )
        ).scalar()
        return float(result) if result else 0.0
    
    def get_users_by_role(self) -> Dict[str, int]:
        """Get user count by role"""
        roles = {}
        for role in UserRole:
            count = self.db.query(User).filter(User.role == role).count()
            roles[role.value] = count
        return roles
    
    def get_recent_payments(self, limit: int = 10) -> List[Dict]:
        """Get recent successful payments"""
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
    
    def get_dashboard_stats(self) -> Dict:
        """Get comprehensive dashboard statistics"""
        now = datetime.utcnow()
        
        # Active users (not expired)
        active_users = self.db.query(User).filter(
            and_(
                User.role != UserRole.BANNED,
                User.is_active == True,
                or_(
                    User.expires_at.is_(None),
                    User.expires_at > now
                )
            )
        ).count()
        
        # Active paid subscriptions
        active_paid = self.db.query(User).filter(
            and_(
                User.role == UserRole.USER,
                User.is_active == True,
                User.expires_at > now,
                User.source == "paid"
            )
        ).count()
        
        # Total users
        total_users = self.db.query(User).count()
        
        # Revenue (last 30 days)
        revenue_30d = self.get_revenue(30)
        revenue_today = self.get_revenue_today()
        
        # Promo issued (last 30 days)
        promo_30d = self.get_promo_issued_count(30)
        
        return {
            "active_users": active_users,
            "active_paid_subscriptions": active_paid,
            "total_users": total_users,
            "revenue_30d": revenue_30d,
            "revenue_today": revenue_today,
            "promo_issued_30d": promo_30d,
            "users_by_role": self.get_users_by_role()
        }

