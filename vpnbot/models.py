"""
Database models for Anomaly VPN Bot
"""
from datetime import datetime
from typing import Optional
from sqlalchemy import (
    Column, Integer, String, BigInteger, DateTime, 
    Boolean, Float, Enum as SQLEnum, Text
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func
import enum

Base = declarative_base()


class UserRole(str, enum.Enum):
    """User roles"""
    ADMIN = "ADMIN"
    USER = "USER"
    PROMO = "PROMO"
    BANNED = "BANNED"


class PaymentMethod(str, enum.Enum):
    """Payment methods"""
    YOOKASSA = "yookassa"
    TELEGRAM = "telegram"
    CRYPTO = "crypto"
    MANUAL = "manual"


class PaymentStatus(str, enum.Enum):
    """Payment statuses"""
    PENDING = "pending"
    PROCESSING = "processing"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"
    REFUNDED = "refunded"


class User(Base):
    """User model"""
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    telegram_id = Column(BigInteger, unique=True, index=True, nullable=False)
    username = Column(String(255), nullable=True)
    first_name = Column(String(255), nullable=True)
    last_name = Column(String(255), nullable=True)
    role = Column(SQLEnum(UserRole), default=UserRole.PROMO, nullable=False)
    expires_at = Column(DateTime, nullable=True)
    traffic_limit_gb = Column(Float, default=0.0, nullable=False)
    used_traffic_gb = Column(Float, default=0.0, nullable=False)
    max_devices = Column(Integer, default=1, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)
    last_active = Column(DateTime, nullable=True)
    source = Column(String(50), default="manual", nullable=False)  # paid, promo, manual
    node_assigned = Column(String(100), nullable=True)
    marzban_uuid = Column(String(255), nullable=True)  # UUID in Marzban
    is_active = Column(Boolean, default=True, nullable=False)
    
    def __repr__(self):
        return f"<User(telegram_id={self.telegram_id}, role={self.role})>"
    
    @property
    def is_expired(self) -> bool:
        """Check if user subscription is expired"""
        if self.role == UserRole.ADMIN:
            return False
        if not self.expires_at:
            return True
        return datetime.utcnow() > self.expires_at
    
    @property
    def traffic_remaining_gb(self) -> float:
        """Calculate remaining traffic"""
        return max(0.0, self.traffic_limit_gb - self.used_traffic_gb)
    
    @property
    def is_traffic_exceeded(self) -> bool:
        """Check if traffic limit exceeded"""
        return self.used_traffic_gb >= self.traffic_limit_gb


class Payment(Base):
    """Payment model"""
    __tablename__ = "payments"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    telegram_id = Column(BigInteger, nullable=False, index=True)
    amount = Column(Float, nullable=False)
    currency = Column(String(10), default="RUB", nullable=False)
    payment_method = Column(SQLEnum(PaymentMethod), nullable=False)
    status = Column(SQLEnum(PaymentStatus), default=PaymentStatus.PENDING, nullable=False)
    payment_id = Column(String(255), unique=True, nullable=True)  # External payment ID
    yookassa_payment_id = Column(String(255), nullable=True)
    telegram_payment_charge_id = Column(String(255), nullable=True)
    crypto_tx_hash = Column(String(255), nullable=True)  # For crypto payments
    provider_payment_id = Column(String(255), nullable=True)  # Generic payment ID
    description = Column(Text, nullable=True)
    created_at = Column(DateTime, default=func.now(), nullable=False)
    completed_at = Column(DateTime, nullable=True)
    extra_data = Column(Text, nullable=True)  # JSON string for additional data (renamed from metadata to avoid SQLAlchemy conflict)
    
    def __repr__(self):
        return f"<Payment(id={self.id}, user_id={self.user_id}, status={self.status})>"


class SubscriptionPlan(Base):
    """Subscription plan model"""
    __tablename__ = "subscription_plans"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    duration_days = Column(Integer, nullable=False)
    traffic_limit_gb = Column(Float, nullable=False)
    max_devices = Column(Integer, default=1, nullable=False)
    price = Column(Float, nullable=False)
    currency = Column(String(10), default="RUB", nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)
    
    def __repr__(self):
        return f"<SubscriptionPlan(name={self.name}, price={self.price})>"


class PromoCode(Base):
    """Promo code model"""
    __tablename__ = "promo_codes"
    
    id = Column(Integer, primary_key=True, index=True)
    code = Column(String(100), unique=True, index=True, nullable=False)
    duration_days = Column(Integer, nullable=False)
    traffic_limit_gb = Column(Float, nullable=False)
    max_uses = Column(Integer, default=1, nullable=False)
    used_count = Column(Integer, default=0, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)
    expires_at = Column(DateTime, nullable=True)
    
    def __repr__(self):
        return f"<PromoCode(code={self.code}, used={self.used_count}/{self.max_uses})>"
    
    @property
    def is_available(self) -> bool:
        """Check if promo code is available"""
        if not self.is_active:
            return False
        if self.used_count >= self.max_uses:
            return False
        if self.expires_at and datetime.utcnow() > self.expires_at:
            return False
        return True


class Node(Base):
    """VPN Node model"""
    __tablename__ = "nodes"
    
    id = Column(Integer, primary_key=True, index=True)
    node_id = Column(String(100), unique=True, index=True, nullable=False)
    name = Column(String(255), nullable=False)
    api_url = Column(String(500), nullable=False)
    username = Column(String(255), nullable=False)
    password = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    current_users = Column(Integer, default=0, nullable=False)
    max_users = Column(Integer, default=0, nullable=False)  # 0 = unlimited
    created_at = Column(DateTime, default=func.now(), nullable=False)
    last_check = Column(DateTime, nullable=True)
    
    def __repr__(self):
        return f"<Node(node_id={self.node_id}, name={self.name})>"


class TrialAccess(Base):
    """Trial/Free access model"""
    __tablename__ = "trial_access"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    telegram_id = Column(BigInteger, nullable=False, index=True)
    duration_days = Column(Integer, nullable=False)
    traffic_limit_gb = Column(Float, nullable=False)
    started_at = Column(DateTime, default=func.now(), nullable=False)
    expires_at = Column(DateTime, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    source = Column(String(50), default="trial", nullable=False)  # trial, free, promo
    
    def __repr__(self):
        return f"<TrialAccess(user_id={self.user_id}, expires_at={self.expires_at})>"
    
    @property
    def is_expired(self) -> bool:
        """Check if trial access is expired"""
        return datetime.utcnow() > self.expires_at


class SystemLog(Base):
    """System log model"""
    __tablename__ = "system_logs"
    
    id = Column(Integer, primary_key=True, index=True)
    log_type = Column(String(50), nullable=False, index=True)  # payment, api, user, node
    level = Column(String(20), default="INFO", nullable=False)  # INFO, WARNING, ERROR
    message = Column(Text, nullable=False)
    user_id = Column(Integer, nullable=True, index=True)
    metadata = Column(Text, nullable=True)  # JSON string
    created_at = Column(DateTime, default=func.now(), nullable=False, index=True)
    
    def __repr__(self):
        return f"<SystemLog(type={self.log_type}, level={self.level})>"


class UserSession(Base):
    """User session model for analytics"""
    __tablename__ = "user_sessions"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=False, index=True)
    telegram_id = Column(BigInteger, nullable=False, index=True)
    session_start = Column(DateTime, default=func.now(), nullable=False)
    session_end = Column(DateTime, nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    actions_count = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False, index=True)
    
    def __repr__(self):
        return f"<UserSession(user_id={self.user_id}, duration={self.duration_seconds}s)>"

