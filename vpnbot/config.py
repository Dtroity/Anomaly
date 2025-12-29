"""
Configuration module for Anomaly VPN Bot
"""
import os
import json
from typing import List, Dict, Optional
from pydantic_settings import BaseSettings
from pydantic import Field


class Settings(BaseSettings):
    """Application settings"""
    
    # Telegram
    bot_token: str = Field(..., env="BOT_TOKEN")
    admin_ids: str = Field(..., env="ADMIN_IDS")
    
    # Database
    db_name: str = Field(default="anomaly", env="DB_NAME")
    db_user: str = Field(default="anomaly", env="DB_USER")
    db_password: str = Field(..., env="DB_PASSWORD")
    db_host: str = Field(default="db", env="DB_HOST")
    db_port: int = Field(default=5432, env="DB_PORT")
    
    # Marzban (локально на Control Server)
    marzban_api_url: str = Field(default="http://marzban:62050", env="MARZBAN_API_URL")
    marzban_username: str = Field(default="root", env="MARZBAN_USERNAME")
    marzban_password: str = Field(..., env="MARZBAN_PASSWORD")
    
    # YooKassa
    yookassa_shop_id: str = Field(..., env="YOOKASSA_SHOP_ID")
    yookassa_secret_key: str = Field(..., env="YOOKASSA_SECRET_KEY")
    yookassa_test_mode: bool = Field(default=True, env="YOOKASSA_TEST_MODE")
    
    # Telegram Payments
    telegram_payment_provider_token: Optional[str] = Field(
        default=None, env="TELEGRAM_PAYMENT_PROVIDER_TOKEN"
    )
    
    # Crypto Payments (опционально)
    crypto_wallet_address: Optional[str] = Field(
        default=None, env="CRYPTO_WALLET_ADDRESS"
    )
    crypto_network: str = Field(default="TRC20", env="CRYPTO_NETWORK")
    
    # Application
    app_name: str = Field(default="Anomaly Connect", env="APP_NAME")
    app_url: str = Field(..., env="APP_URL")
    panel_url: str = Field(default="https://panel.anomaly-connect.online", env="PANEL_URL")
    api_secret_key: str = Field(..., env="API_SECRET_KEY")
    
    # VPN Settings
    default_traffic_limit_gb: int = Field(default=100, env="DEFAULT_TRAFFIC_LIMIT_GB")
    default_max_devices: int = Field(default=3, env="DEFAULT_MAX_DEVICES")
    free_trial_days: int = Field(default=7, env="FREE_TRIAL_DAYS")
    free_trial_traffic_gb: int = Field(default=5, env="FREE_TRIAL_TRAFFIC_GB")
    
    # Nodes
    nodes_config: str = Field(default="[]", env="NODES_CONFIG")
    
    class Config:
        env_file = ".env"
        case_sensitive = False
    
    @property
    def admin_ids_list(self) -> List[int]:
        """Parse admin IDs from comma-separated string"""
        return [int(uid.strip()) for uid in self.admin_ids.split(",") if uid.strip()]
    
    @property
    def nodes(self) -> List[Dict]:
        """Parse nodes configuration from JSON string"""
        try:
            return json.loads(self.nodes_config) if self.nodes_config else []
        except json.JSONDecodeError:
            return []
    
    @property
    def database_url(self) -> str:
        """Get database connection URL"""
        return f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"


# Global settings instance
settings = Settings()
