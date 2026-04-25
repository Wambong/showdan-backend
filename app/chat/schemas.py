from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class UserRef(BaseModel):
    id: UUID


class UserResponse(BaseModel):
    id: UUID
    name: str
    email: str | None = None
    picture: str | None = None

    model_config = ConfigDict(from_attributes=True)


class ConversationCreate(BaseModel):
    user_one: UserRef
    user_two: UserRef


class MessageCreate(BaseModel):
    sender_id: UUID
    body: str = Field(min_length=1, max_length=4000)
    media_url: str | None = None
    media_type: str | None = None
    media_name: str | None = None


class ChatMessageResponse(BaseModel):
    id: UUID
    conversation_id: UUID
    sender_id: UUID
    body: str
    media_url: str | None = None
    media_type: str | None = None
    media_name: str | None = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ChatConversationResponse(BaseModel):
    id: UUID
    user_a_id: UUID
    user_b_id: UUID
    created_at: datetime
    updated_at: datetime
    last_message: ChatMessageResponse | None = None

    model_config = ConfigDict(from_attributes=True)
