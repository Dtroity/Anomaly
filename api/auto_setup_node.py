"""
API endpoint для автоматической настройки ноды
"""
import subprocess
import os
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/api/auto-setup", tags=["Auto Setup"])


class NodeSetupRequest(BaseModel):
    node_ip: str
    node_user: str = "root"
    node_password: str
    node_name: str = "Node 1"
    node_port: int = 62050
    api_port: int = 62051
    control_server_url: str = "https://panel.anomaly-connect.online"


@router.post("/node")
async def auto_setup_node(request: NodeSetupRequest):
    """
    Автоматическая настройка ноды через SSH
    """
    try:
        # Получить путь к скрипту
        script_path = os.path.join(os.path.dirname(__file__), "..", "auto-setup-node.sh")
        script_path = os.path.abspath(script_path)
        
        if not os.path.exists(script_path):
            raise HTTPException(
                status_code=500,
                detail=f"Script not found: {script_path}"
            )
        
        # Выполнить скрипт
        result = subprocess.run(
            [
                "bash", script_path,
                request.node_ip,
                request.node_user,
                request.node_password,
                request.node_name,
                str(request.node_port),
                str(request.api_port),
                request.control_server_url
            ],
            capture_output=True,
            text=True,
            timeout=300  # 5 минут таймаут
        )
        
        if result.returncode != 0:
            raise HTTPException(
                status_code=500,
                detail=f"Setup failed: {result.stderr}"
            )
        
        return {
            "success": True,
            "message": "Node setup completed successfully",
            "output": result.stdout
        }
        
    except subprocess.TimeoutExpired:
        raise HTTPException(
            status_code=500,
            detail="Setup timeout (exceeded 5 minutes)"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Setup error: {str(e)}"
        )

