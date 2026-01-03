"""
Marzban API integration service
"""
import logging
import aiohttp
import asyncio
import threading
import concurrent.futures
import uuid
import json
import os
from typing import Dict, Optional, List
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

# #region agent log
DEBUG_LOG_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), ".cursor", "debug.log")
def _debug_log(location: str, message: str, data: dict = None, hypothesis_id: str = None):
    try:
        log_entry = {
            "timestamp": int(datetime.utcnow().timestamp() * 1000),
            "location": location,
            "message": message,
            "data": data or {},
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": hypothesis_id
        }
        with open(DEBUG_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(log_entry, ensure_ascii=False) + "\n")
    except Exception:
        pass
# #endregion


class MarzbanService:
    """Service for interacting with Marzban API"""
    
    def __init__(self, api_url: str, username: str, password: str):
        self.api_url = api_url.rstrip('/')
        self.username = username
        self.password = password
        self._token: Optional[str] = None
        self._token_expires: Optional[datetime] = None
    
    async def _get_token(self) -> str:
        """Get or refresh authentication token"""
        if self._token and self._token_expires:
            if datetime.utcnow() < self._token_expires:
                return self._token
        
        # Marzban uses OAuth2PasswordRequestForm (form-data)
        form_data = aiohttp.FormData()
        form_data.add_field('username', self.username)
        form_data.add_field('password', self.password)
        
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.api_url}/api/admin/token",
                data=form_data,
                ssl=False
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    self._token = data.get("access_token")
                    # Token expires in 30 minutes, refresh 5 minutes early
                    self._token_expires = datetime.utcnow() + timedelta(minutes=25)
                    return self._token
                else:
                    error_text = await response.text()
                    raise Exception(f"Failed to get token: {response.status} - {error_text}")
    
    async def _request(
        self, 
        method: str, 
        endpoint: str, 
        json_data: Optional[Dict] = None,
        params: Optional[Dict] = None
    ) -> Dict:
        """Make authenticated request to Marzban API"""
        # #region agent log
        _debug_log(
            "marzban.py:_request:entry",
            f"API request started",
            {"method": method, "endpoint": endpoint, "has_json": json_data is not None, "has_params": params is not None},
            "A"
        )
        # #endregion
        
        token = await self._get_token()
        # Marzban uses /api for all endpoints (system, user, etc.)
        # No /api/v1 prefix needed
        url = f"{self.api_url}/api{endpoint}"
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        # #region agent log
        _debug_log(
            "marzban.py:_request:before_request",
            f"Before API request",
            {"url": url, "method": method, "endpoint": endpoint},
            "A"
        )
        # #endregion
        
        async with aiohttp.ClientSession() as session:
            async with session.request(
                method=method,
                url=url,
                headers=headers,
                json=json_data,
                params=params,
                ssl=False
            ) as response:
                # #region agent log
                _debug_log(
                    "marzban.py:_request:response",
                    f"API response received",
                    {"status": response.status, "endpoint": endpoint, "method": method},
                    "A"
                )
                # #endregion
                
                if response.status in [200, 201]:
                    result = await response.json()
                    # #region agent log
                    _debug_log(
                        "marzban.py:_request:success",
                        f"API request successful",
                        {"status": response.status, "endpoint": endpoint, "result_keys": list(result.keys()) if isinstance(result, dict) else "not_dict"},
                        "A"
                    )
                    # #endregion
                    return result
                elif response.status == 204:
                    # #region agent log
                    _debug_log(
                        "marzban.py:_request:no_content",
                        f"API request returned 204 No Content",
                        {"endpoint": endpoint},
                        "A"
                    )
                    # #endregion
                    return {}
                elif response.status == 404:
                    error_text = await response.text()
                    # #region agent log
                    _debug_log(
                        "marzban.py:_request:not_found",
                        f"API request returned 404",
                        {"endpoint": endpoint, "error": error_text},
                        "A"
                    )
                    # #endregion
                    raise Exception(f"Not found: {error_text}")
                else:
                    error_text = await response.text()
                    # #region agent log
                    _debug_log(
                        "marzban.py:_request:error",
                        f"API request failed",
                        {"status": response.status, "endpoint": endpoint, "error": error_text},
                        "A"
                    )
                    # #endregion
                    raise Exception(
                        f"Marzban API error: {method} {endpoint} - "
                        f"{response.status} - {error_text}"
                    )
    
    async def create_user(
        self,
        username: str,
        data_limit: Optional[int] = None,
        expire_date: Optional[datetime] = None,
        proxies: Optional[Dict] = None
    ) -> Dict:
        """Create new user in Marzban"""
        # #region agent log
        _debug_log(
            "marzban.py:create_user:entry",
            f"Creating user",
            {"username": username, "has_data_limit": data_limit is not None, "has_expire_date": expire_date is not None, "has_proxies": proxies is not None},
            "B"
        )
        # #endregion
        
        # If no proxies specified, try to use available protocols
        # Try to get available inbounds to determine which protocol to use
        if not proxies:
            try:
                inbounds = await self._request("GET", "/inbounds")
                # Check which protocols are available
                # inbounds can be a dict like {"vmess": [...], "vless": [...]} or empty dict {}
                if not isinstance(inbounds, dict):
                    inbounds = {}
                
                available_protocols = list(inbounds.keys()) if inbounds else []
                
                # Try protocols in order: vmess, vless, trojan, shadowsocks
                # inbounds is a dict like {"vmess": [...], "vless": [...]}
                if "vmess" in inbounds and inbounds.get("vmess"):
                    proxies = {
                        "vmess": {
                            "id": str(uuid.uuid4())
                        }
                    }
                elif "vless" in inbounds and inbounds.get("vless"):
                    proxies = {
                        "vless": {
                            "id": str(uuid.uuid4()),
                            "flow": ""
                        }
                    }
                elif "trojan" in inbounds and inbounds.get("trojan"):
                    proxies = {
                        "trojan": {
                            "password": str(uuid.uuid4())
                        }
                    }
                elif "shadowsocks" in inbounds and inbounds.get("shadowsocks"):
                    proxies = {
                        "shadowsocks": {
                            "password": str(uuid.uuid4()),
                            "method": "chacha20-ietf-poly1305"
                        }
                    }
                else:
                    # If no protocols found, raise error with helpful message
                    logger.error("No proxy protocols available in Marzban")
                    raise Exception(
                        "No proxy protocols available. Please configure inbounds in Marzban panel: "
                        "https://panel.anomaly-connect.online -> Settings -> Inbounds"
                    )
            except Exception as e:
                error_msg = str(e)
                if "No proxy protocols available" in error_msg:
                    raise
                logger.warning(f"Could not get inbounds: {e}")
                # If we can't get inbounds, raise error with helpful message
                raise Exception(
                    f"Could not determine available protocols: {error_msg}. "
                    "Please configure inbounds in Marzban panel: "
                    "https://panel.anomaly-connect.online -> Settings -> Inbounds"
                )
        elif "vless" in proxies and "id" in proxies["vless"]:
            # Ensure vless id is a valid UUID
            try:
                uuid.UUID(proxies["vless"]["id"])
            except (ValueError, TypeError):
                proxies["vless"]["id"] = str(uuid.uuid4())
        elif "vmess" in proxies and "id" in proxies["vmess"]:
            # Ensure vmess id is a valid UUID
            try:
                uuid.UUID(proxies["vmess"]["id"])
            except (ValueError, TypeError):
                proxies["vmess"]["id"] = str(uuid.uuid4())
        
        payload = {
            "username": username,
            "proxies": proxies
        }
        
        if data_limit:
            payload["data_limit"] = data_limit * 1024 * 1024 * 1024  # Convert GB to bytes
        
        if expire_date:
            payload["expire"] = int(expire_date.timestamp())
        
        # #region agent log
        _debug_log(
            "marzban.py:create_user:before_request",
            f"Before creating user via API",
            {"username": username, "payload_keys": list(payload.keys())},
            "B"
        )
        # #endregion
        
        result = await self._request("POST", "/user", json_data=payload)
        
        # #region agent log
        _debug_log(
            "marzban.py:create_user:success",
            f"User created successfully",
            {"username": username, "result_username": result.get("username") if isinstance(result, dict) else None},
            "B"
        )
        # #endregion
        
        return result
    
    async def get_user(self, username: str) -> Optional[Dict]:
        """Get user information"""
        try:
            return await self._request("GET", f"/user/{username}")
        except Exception as e:
            if "404" in str(e) or "not found" in str(e).lower():
                return None
            raise
    
    async def update_user(
        self,
        username: str,
        data_limit: Optional[int] = None,
        expire_date: Optional[datetime] = None,
        proxies: Optional[Dict] = None
    ) -> Dict:
        """Update user in Marzban
        
        Args:
            username: Username to update
            data_limit: Data limit in bytes (not GB)
            expire_date: Expiration date
            proxies: Proxy configuration (if None and user has no proxies, will add them)
        """
        # First, get current user to check if they have proxies
        current_user = await self.get_user(username)
        if not current_user:
            raise Exception(f"User {username} not found")
        
        # If user has no proxies and none provided, add them
        user_proxies = current_user.get("proxies", {})
        if not user_proxies and proxies is None:
            # User has no proxies, need to add them
            try:
                inbounds = await self._request("GET", "/inbounds")
                if not isinstance(inbounds, dict):
                    inbounds = {}
                
                # Try protocols in order: vmess, vless, trojan, shadowsocks
                if "vmess" in inbounds and inbounds.get("vmess"):
                    proxies = {
                        "vmess": {
                            "id": str(uuid.uuid4())
                        }
                    }
                elif "vless" in inbounds and inbounds.get("vless"):
                    proxies = {
                        "vless": {
                            "id": str(uuid.uuid4()),
                            "flow": ""
                        }
                    }
                elif "trojan" in inbounds and inbounds.get("trojan"):
                    proxies = {
                        "trojan": {
                            "password": str(uuid.uuid4())
                        }
                    }
                elif "shadowsocks" in inbounds and inbounds.get("shadowsocks"):
                    proxies = {
                        "shadowsocks": {
                            "password": str(uuid.uuid4()),
                            "method": "chacha20-ietf-poly1305"
                        }
                    }
                else:
                    logger.error("No proxy protocols available in Marzban")
                    raise Exception(
                        "No proxy protocols available. Please configure inbounds in Marzban panel: "
                        "https://panel.anomaly-connect.online -> Settings -> Inbounds"
                    )
            except Exception as e:
                error_msg = str(e)
                if "No proxy protocols available" in error_msg:
                    raise
                logger.warning(f"Could not get inbounds: {e}")
                raise Exception(
                    f"Could not determine available protocols: {error_msg}. "
                    "Please configure inbounds in Marzban panel: "
                    "https://panel.anomaly-connect.online -> Settings -> Inbounds"
                )
        
        payload = {}
        
        if data_limit is not None:
            # data_limit is already in bytes, pass directly
            payload["data_limit"] = data_limit
        
        if expire_date is not None:
            payload["expire"] = int(expire_date.timestamp())
        
        if proxies is not None:
            payload["proxies"] = proxies
        
        return await self._request("PUT", f"/user/{username}", json_data=payload)
    
    async def delete_user(self, username: str) -> bool:
        """Delete user from Marzban"""
        # #region agent log
        _debug_log(
            "marzban.py:delete_user:entry",
            f"Deleting user",
            {"username": username},
            "C"
        )
        # #endregion
        
        try:
            # #region agent log
            _debug_log(
                "marzban.py:delete_user:before_request",
                f"Before deleting user via API",
                {"username": username},
                "C"
            )
            # #endregion
            
            await self._request("DELETE", f"/user/{username}")
            
            # #region agent log
            _debug_log(
                "marzban.py:delete_user:success",
                f"User deleted successfully",
                {"username": username},
                "C"
            )
            # #endregion
            
            return True
        except Exception as e:
            # #region agent log
            _debug_log(
                "marzban.py:delete_user:error",
                f"Error deleting user",
                {"username": username, "error": str(e)},
                "C"
            )
            # #endregion
            logger.error(f"Error deleting user {username}: {e}")
            return False
    
    async def get_user_usage(self, username: str) -> Dict:
        """Get user traffic usage"""
        try:
            return await self._request("GET", f"/user/{username}/usage")
        except Exception as e:
            logger.error(f"Error getting usage for {username}: {e}")
            return {}
    
    async def get_system_stats(self) -> Dict:
        """Get system statistics"""
        try:
            return await self._request("GET", "/system")
        except Exception as e:
            logger.error(f"Error getting system stats: {e}")
            return {}
    
    async def get_users(self, offset: int = 0, limit: int = 100) -> List[Dict]:
        """Get list of users"""
        try:
            response = await self._request("GET", "/users", params={"offset": offset, "limit": limit})
            return response.get("users", [])
        except Exception as e:
            logger.error(f"Error getting users: {e}")
            return []
    
    # Synchronous wrappers for compatibility
    def create_user_sync(
        self,
        username: str,
        data_limit: Optional[int] = None,
        expire_date: Optional[datetime] = None,
        proxies: Optional[Dict] = None
    ) -> Dict:
        """Synchronous wrapper for create_user"""
        return asyncio.run(self.create_user(username, data_limit, expire_date, proxies))
    
    def get_user_sync(self, username: str) -> Optional[Dict]:
        """Synchronous wrapper for get_user"""
        return asyncio.run(self.get_user(username))
    
    def update_user_sync(
        self,
        username: str,
        data_limit: Optional[int] = None,
        expire_date: Optional[datetime] = None,
        proxies: Optional[Dict] = None
    ) -> Dict:
        """Synchronous wrapper for update_user"""
        return asyncio.run(self.update_user(username, data_limit, expire_date, proxies))
    
    def delete_user_sync(self, username: str) -> bool:
        """Synchronous wrapper for delete_user"""
        return asyncio.run(self.delete_user(username))
    
    def get_user_usage_sync(self, username: str) -> Dict:
        """Synchronous wrapper for get_user_usage"""
        return asyncio.run(self.get_user_usage(username))
    
    def get_system_stats_sync(self) -> Dict:
        """Synchronous wrapper for get_system_stats"""
        try:
            # Try to get existing event loop
            loop = asyncio.get_event_loop()
            if loop.is_running():
                # If loop is running, create a new event loop in a thread
                import concurrent.futures
                import threading
                
                result = None
                exception = None
                
                def run_in_thread():
                    nonlocal result, exception
                    try:
                        new_loop = asyncio.new_event_loop()
                        asyncio.set_event_loop(new_loop)
                        result = new_loop.run_until_complete(self.get_system_stats())
                        new_loop.close()
                    except Exception as e:
                        exception = e
                
                thread = threading.Thread(target=run_in_thread)
                thread.start()
                thread.join(timeout=10)
                
                if exception:
                    raise exception
                if result is None:
                    raise TimeoutError("Timeout waiting for system stats")
                return result
            else:
                return loop.run_until_complete(self.get_system_stats())
        except RuntimeError:
            # No event loop, create new one
            return asyncio.run(self.get_system_stats())
    
    async def get_subscription_url(self, username: str, client_type: str = "v2ray") -> Optional[str]:
        """Get subscription URL for user
        
        Args:
            username: Username
            client_type: Client type (v2ray, clash, etc.). Default is v2ray for V2RayTun compatibility
        """
        try:
            user = await self.get_user(username)
            if not user:
                return None
            
            # Marzban returns subscription_url in user response
            subscription_url = user.get("subscription_url", "")
            
            if subscription_url:
                # Extract token from subscription URL
                # Format: /sub/{token} or /sub/{token}/
                if subscription_url.startswith("/"):
                    # Remove leading slash and trailing slash if present
                    token = subscription_url.strip("/").replace("/sub/", "").replace("sub/", "")
                    # Use public API URL with client type for better compatibility
                    base_url = "https://api.anomaly-connect.online"
                    if client_type == "v2ray":
                        # For V2RayTun, use /v2ray endpoint which returns base64-encoded v2ray links
                        # V2RayTun requires base64-encoded format, not JSON
                        # The /v2ray endpoint ensures proper format for V2Ray clients
                        return f"{base_url}/sub/{token}/v2ray"
                    return f"{base_url}{subscription_url}"
                
                # If URL is already absolute, ensure it uses HTTPS
                if subscription_url.startswith("http://"):
                    subscription_url = subscription_url.replace("http://", "https://", 1)
                
                # For absolute URLs, extract token and rebuild with /v2ray endpoint if needed
                if client_type == "v2ray" and "/v2ray" not in subscription_url:
                    # Extract token from absolute URL (format: https://domain/sub/token or https://domain/sub/token/)
                    import re
                    match = re.search(r'/sub/([^/]+)', subscription_url)
                    if match:
                        token = match.group(1)
                        base_url = "https://api.anomaly-connect.online"
                        return f"{base_url}/sub/{token}/v2ray"
                    # If pattern doesn't match, try to add /v2ray at the end
                    if not subscription_url.endswith("/v2ray"):
                        subscription_url = subscription_url.rstrip("/") + "/v2ray"
                
                return subscription_url
            
            return None
        except Exception as e:
            logger.error(f"Error getting subscription URL for {username}: {e}")
            return None
    
    def get_subscription_url_sync(self, username: str) -> Optional[str]:
        """Synchronous wrapper for get_subscription_url"""
        return asyncio.run(self.get_subscription_url(username))
    
    async def revoke_subscription(self, username: str) -> Dict:
        """Revoke user subscription"""
        # #region agent log
        _debug_log(
            "marzban.py:revoke_subscription:entry",
            f"Revoking subscription",
            {"username": username},
            "D"
        )
        # #endregion
        
        try:
            # #region agent log
            _debug_log(
                "marzban.py:revoke_subscription:before_request",
                f"Before revoking subscription via API",
                {"username": username},
                "D"
            )
            # #endregion
            
            result = await self._request("POST", f"/user/{username}/revoke_sub")
            
            # #region agent log
            _debug_log(
                "marzban.py:revoke_subscription:success",
                f"Subscription revoked successfully",
                {"username": username, "result_username": result.get("username") if isinstance(result, dict) else None},
                "D"
            )
            # #endregion
            
            return result
        except Exception as e:
            # #region agent log
            _debug_log(
                "marzban.py:revoke_subscription:error",
                f"Error revoking subscription",
                {"username": username, "error": str(e)},
                "D"
            )
            # #endregion
            logger.error(f"Error revoking subscription for {username}: {e}")
            raise

