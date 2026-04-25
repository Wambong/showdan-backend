import uuid
from datetime import datetime

from sqlalchemy import Column, DateTime, String
from sqlalchemy.dialects.postgresql import UUID

from app.db.database import Base


class ChatUser(Base):
    __tablename__ = "chat_users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    provider = Column(String(50), default="google", nullable=False)
    provider_user_id = Column(String(255), unique=True, nullable=False)
    email = Column(String(255), unique=True)
    name = Column(String(255), nullable=False)
    picture = Column(String(500))
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
