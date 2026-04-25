from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class NewsBase(BaseModel):
    title: str = Field(min_length=1)
    content: str = Field(min_length=1)
    summary: str | None = None
    category: str | None = None
    lat: float | None = None
    lng: float | None = None
    location_name: str | None = None
    image_url: str | None = None
    source_url: str | None = None
    is_published: bool = False


class NewsCreate(NewsBase):
    author_name: str | None = None


class NewsUpdate(NewsBase):
    pass


class NewsResponse(NewsBase):
    id: int
    author_name: str | None = None
    total_likes: int = 0
    total_dislikes: int = 0
    total_comments: int = 0
    date_created: datetime
    date_updated: datetime
    created_at: datetime
    updated_at: datetime


class NewsNearbyResponse(BaseModel):
    id: int
    title: str
    summary: str | None = None
    category: str | None = None
    location_name: str | None = None
    distance_meters: float
    created_at: datetime


class NewsCommentCreate(BaseModel):
    user_name: str | None = Field(default=None, max_length=255)
    comment: str = Field(min_length=1)
    parent_comment_id: int | None = None


class NewsCommentUpdate(BaseModel):
    user_name: str | None = Field(default=None, max_length=255)
    comment: str = Field(min_length=1)


class NewsCommentResponse(BaseModel):
    id: int
    parent_comment_id: int | None = None
    user_name: str
    comment: str
    depth: int
    is_deleted: bool
    created_at: datetime
    updated_at: datetime


class NewsReactionCreate(BaseModel):
    user_name: str | None = Field(default=None, max_length=255)
    reaction_type: Literal["like", "dislike", "emoji"]
    emoji: str | None = None


class NewsReactionDelete(NewsReactionCreate):
    pass


class NewsReactionSummary(BaseModel):
    reaction_type: str
    emoji: str | None = None
    total: int
    users: list[str]


class IdResponse(BaseModel):
    id: int


class StatusResponse(BaseModel):
    ok: bool


class ElasticsearchSyncResponse(BaseModel):
    processed: int
    failed: int
