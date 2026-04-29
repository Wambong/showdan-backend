from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.AIRAG.schemas import (
    RagConversationResponse,
    RagHealthResponse,
    RagQueryRequest,
    RagQueryResponse,
    RagSourcesResponse,
)
from app.AIRAG.services import (
    AIRAG_LLM_MODEL,
    OLLAMA_BASE_URL,
    build_prompt,
    call_llama,
    fallback_answer,
    list_conversations,
    ollama_available,
    retrieve_contexts,
    save_conversation,
)
from app.db.database import get_db

router = APIRouter(prefix="/airag", tags=["ShowE AI"])


@router.get("/health", response_model=RagHealthResponse)
def health():
    return {
        "ok": True,
        "llm_available": ollama_available(),
        "model": AIRAG_LLM_MODEL,
        "ollama_base_url": OLLAMA_BASE_URL,
    }


@router.get("/sources", response_model=RagSourcesResponse)
def sources():
    return {"sources": ["news", "performers", "chat_users"]}


@router.post("/query", response_model=RagQueryResponse)
def query(payload: RagQueryRequest, db: Session = Depends(get_db)):
    contexts = retrieve_contexts(db, payload.question, payload.sources, payload.top_k)
    answer = ""
    used_llm = False
    if payload.use_llm:
        answer, used_llm = call_llama(build_prompt(payload.question, contexts))
    if not answer:
        answer = fallback_answer(payload.question, contexts)
    model = AIRAG_LLM_MODEL if used_llm else None
    save_conversation(db, payload.question, answer, model, contexts)
    return {
        "answer": answer,
        "question": payload.question,
        "model": model,
        "used_llm": used_llm,
        "contexts": contexts,
    }


@router.get("/conversations", response_model=list[RagConversationResponse])
def conversations(limit: int = Query(20, ge=1, le=100), db: Session = Depends(get_db)):
    return list_conversations(db, limit)
