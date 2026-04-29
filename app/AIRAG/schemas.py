from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

RagSource = Literal["news", "performers", "chat_users"]


class RagQueryRequest(BaseModel):
    question: str = Field(min_length=1, max_length=4000)
    sources: list[RagSource] = Field(default_factory=lambda: ["news", "performers"])
    top_k: int = Field(default=6, ge=1, le=20)
    use_llm: bool = True


class RagContext(BaseModel):
    source: RagSource
    source_id: str
    title: str
    content: str
    score: float
    metadata: dict = Field(default_factory=dict)


class RagQueryResponse(BaseModel):
    answer: str
    question: str
    model: str | None = None
    used_llm: bool
    contexts: list[RagContext]


class RagConversationResponse(BaseModel):
    id: int
    question: str
    answer: str
    model: str | None = None
    created_at: datetime


class RagHealthResponse(BaseModel):
    ok: bool
    llm_available: bool
    model: str
    ollama_base_url: str


class RagSourcesResponse(BaseModel):
    sources: list[RagSource]
