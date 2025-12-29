"""
VPN Nodes management service
"""
import logging
from typing import List, Dict, Optional
from datetime import datetime
from sqlalchemy.orm import Session

from config import settings
from models import Node
from services.marzban import MarzbanService

logger = logging.getLogger(__name__)


class NodeService:
    """Service for managing VPN nodes"""
    
    def __init__(self, db: Session):
        self.db = db
        self._cache: Optional[List[Dict]] = None
        self._cache_time: Optional[datetime] = None
        self._cache_ttl = 300  # 5 minutes
    
    def _load_nodes_from_config(self) -> List[Dict]:
        """Load nodes from configuration"""
        nodes = []
        
        # Add default node from config
        nodes.append({
            "id": "default",
            "url": settings.marzban_api_url,
            "username": settings.marzban_username,
            "password": settings.marzban_password,
            "name": "Основная нода"
        })
        
        # Add additional nodes from config
        for node_config in settings.nodes:
            nodes.append({
                "id": node_config.get("id", f"node_{len(nodes)}"),
                "url": node_config.get("url"),
                "username": node_config.get("username", "root"),
                "password": node_config.get("password"),
                "name": node_config.get("name", node_config.get("id"))
            })
        
        return nodes
    
    def _get_nodes_from_db(self) -> List[Node]:
        """Get nodes from database"""
        return self.db.query(Node).filter(Node.is_active == True).all()
    
    def get_available_nodes(self) -> List[Dict]:
        """Get all available nodes with their status"""
        now = datetime.utcnow()
        
        # Check cache
        if self._cache and self._cache_time:
            if (now - self._cache_time).total_seconds() < self._cache_ttl:
                return self._cache
        
        nodes = []
        
        # Get nodes from database first
        db_nodes = self._get_nodes_from_db()
        for db_node in db_nodes:
            try:
                marzban = MarzbanService(
                    api_url=db_node.api_url,
                    username=db_node.username,
                    password=db_node.password
                )
                stats = marzban.get_system_stats()
                
                nodes.append({
                    "id": db_node.node_id,
                    "url": db_node.api_url,
                    "username": db_node.username,
                    "password": db_node.password,
                    "name": db_node.name,
                    "current_users": stats.get("users", {}).get("total", 0),
                    "max_users": db_node.max_users,
                    "load": self._calculate_load(stats, db_node.max_users)
                })
            except Exception as e:
                logger.error(f"Error checking node {db_node.node_id}: {e}")
                continue
        
        # If no DB nodes, use config
        if not nodes:
            config_nodes = self._load_nodes_from_config()
            for node_config in config_nodes:
                try:
                    marzban = MarzbanService(
                        api_url=node_config["url"],
                        username=node_config["username"],
                        password=node_config["password"]
                    )
                    stats = marzban.get_system_stats()
                    
                    nodes.append({
                        "id": node_config["id"],
                        "url": node_config["url"],
                        "username": node_config["username"],
                        "password": node_config["password"],
                        "name": node_config["name"],
                        "current_users": stats.get("users", {}).get("total", 0),
                        "max_users": 0,
                        "load": self._calculate_load(stats, 0)
                    })
                except Exception as e:
                    logger.error(f"Error checking config node {node_config['id']}: {e}")
                    continue
        
        # Update cache
        self._cache = nodes
        self._cache_time = now
        
        return nodes
    
    def _calculate_load(self, stats: Dict, max_users: int) -> float:
        """Calculate node load (0.0 to 1.0)"""
        current = stats.get("users", {}).get("total", 0)
        if max_users == 0:
            # Unlimited capacity, return low load
            return 0.1
        if max_users == 0:
            return 1.0
        return min(1.0, current / max_users)
    
    def select_best_node(self) -> Optional[Dict]:
        """Select node with lowest load"""
        nodes = self.get_available_nodes()
        if not nodes:
            return None
        
        # Sort by load
        nodes_sorted = sorted(nodes, key=lambda x: x.get("load", 1.0))
        return nodes_sorted[0]
    
    def get_node_by_id(self, node_id: str) -> Optional[Dict]:
        """Get specific node by ID"""
        nodes = self.get_available_nodes()
        for node in nodes:
            if node["id"] == node_id:
                return node
        return None
    
    def refresh_cache(self):
        """Force refresh node cache"""
        self._cache = None
        self._cache_time = None

