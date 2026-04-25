import uuid
from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.database import Base


class ChatConversation(Base):
    __tablename__ = "chat_conversations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_a_id = Column(UUID(as_uuid=True), ForeignKey("chat_users.id", ondelete="CASCADE"), nullable=False)
    user_b_id = Column(UUID(as_uuid=True), ForeignKey("chat_users.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    messages = relationship(
        "ChatMessage",
        back_populates="conversation",
        cascade="all, delete-orphan",
        order_by="ChatMessage.created_at",
    )

    __table_args__ = (
        UniqueConstraint("user_a_id", "user_b_id", name="uq_chat_conversation_pair"),
        Index("ix_chat_conversation_a", "user_a_id"),
        Index("ix_chat_conversation_b", "user_b_id"),
    )


class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    conversation_id = Column(
        UUID(as_uuid=True),
        ForeignKey("chat_conversations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sender_id = Column(UUID(as_uuid=True), ForeignKey("chat_users.id", ondelete="CASCADE"), nullable=False)
    body = Column(Text, nullable=False)
    media_url = Column(String(500))
    media_type = Column(String(100))
    media_name = Column(String(255))
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    conversation = relationship("ChatConversation", back_populates="messages")

    __table_args__ = (
        Index("ix_chat_messages_sender", "sender_id"),
    )
