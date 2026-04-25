from pydantic import BaseModel
from datetime import datetime
from typing import Optional, Dict, List, Literal, Any

AuthMethod = Literal['google', 'sms', 'apple']

class AuthLogEntry(BaseModel):
    timestamp: datetime = datetime.utcnow()
    auth_method: AuthMethod
    event_type: str
    user_identifier: str  # email или phone
    ip_address: str
    user_agent: str
    location: Optional[Dict[str, str]] = None
    device_info: Optional[Dict[str, str]] = None
    status: str
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    session_id: Optional[str] = None
    correlation_id: str

    # Поля для разных провайдеров
    provider_user_id: Optional[str] = None
    email: Optional[str] = None
    phone_number: Optional[str] = None
    oauth_scopes: Optional[List[str]] = None
    additional_info: Optional[Dict[str, str]] = None

    def to_dict(self) -> Dict[str, Any]:
        return self.dict(exclude_none=True)
