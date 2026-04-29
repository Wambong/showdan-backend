import os
import re
from typing import Any

import requests
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.AIRAG.schemas import RagContext
from app.db.database import engine

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://host.docker.internal:11434")
AIRAG_LLM_MODEL = os.getenv("AIRAG_LLM_MODEL", "llama3.2")


def install_airag_database() -> None:
    with engine.begin() as connection:
        connection.exec_driver_sql("""
            CREATE TABLE IF NOT EXISTS airag_conversations (
                id BIGSERIAL PRIMARY KEY,
                question TEXT NOT NULL,
                answer TEXT NOT NULL,
                model VARCHAR(100),
                contexts JSONB NOT NULL DEFAULT '[]'::jsonb,
                created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS idx_airag_conversations_created_at
                ON airag_conversations(created_at DESC);
        """)


def retrieve_contexts(db: Session, question: str, sources: list[str], top_k: int) -> list[RagContext]:
    contexts: list[RagContext] = []
    per_source_limit = max(1, top_k)
    if "news" in sources:
        contexts.extend(_retrieve_news(db, question, per_source_limit))
    if "performers" in sources:
        contexts.extend(_retrieve_performers(db, question, per_source_limit))
    if "chat_users" in sources:
        contexts.extend(_retrieve_chat_users(db, question, per_source_limit))
    return sorted(contexts, key=lambda item: item.score, reverse=True)[:top_k]


def _retrieve_news(db: Session, question: str, limit: int) -> list[RagContext]:
    rows = db.execute(
        text("""
            WITH docs AS (
                SELECT
                    id::text AS source_id,
                    title,
                    concat_ws(' ', title, summary, content, category, location_name, author_name) AS document,
                    jsonb_build_object(
                        'category', category,
                        'author_name', author_name,
                        'location_name', location_name,
                        'created_at', created_at
                    ) AS metadata
                FROM news
                WHERE is_published = TRUE
            ),
            ranked AS (
                SELECT
                    source_id,
                    title,
                    document,
                    metadata,
                    ts_rank_cd(
                        to_tsvector('simple', coalesce(document, '')),
                        websearch_to_tsquery('simple', :question)
                    ) AS rank
                FROM docs
            )
            SELECT *
            FROM ranked
            WHERE rank > 0 OR document ILIKE :pattern
            ORDER BY rank DESC, source_id DESC
            LIMIT :limit
        """),
        {"question": question, "pattern": f"%{question}%", "limit": limit},
    ).mappings().all()
    return [
        RagContext(
            source="news",
            source_id=row["source_id"],
            title=row["title"] or "News",
            content=_trim(row["document"]),
            score=float(row["rank"] or 0),
            metadata=dict(row["metadata"] or {}),
        )
        for row in rows
    ]


def _retrieve_performers(db: Session, question: str, limit: int) -> list[RagContext]:
    filters = _extract_performer_filters(db, question)
    structured_rows = []
    if filters:
        structured_rows = db.execute(
            text("""
                SELECT
                    id::text AS source_id,
                    stage_name AS title,
                    concat_ws(
                        ' ',
                        stage_name,
                        first_name,
                        last_name,
                        type::text,
                        about,
                        description,
                        current_city_name,
                        specific_attributes::text
                    ) AS document,
                    jsonb_build_object(
                        'type', type::text,
                        'city', current_city_name,
                        'rating', rating,
                        'hourly_rate', hourly_rate,
                        'first_name', first_name,
                        'last_name', last_name,
                        'photo_url', photo_url
                    ) AS metadata,
                    10.0 AS rank
                FROM performers
                WHERE (:performer_type IS NULL OR type::text = :performer_type)
                  AND (:city IS NULL OR lower(current_city_name) = lower(:city))
                ORDER BY rating DESC NULLS LAST, xp_points DESC NULLS LAST, stage_name ASC
                LIMIT :limit
            """),
            {
                "performer_type": filters.get("type"),
                "city": filters.get("city"),
                "limit": limit,
            },
        ).mappings().all()

    rows = db.execute(
        text("""
            WITH docs AS (
                SELECT
                    id::text AS source_id,
                    stage_name AS title,
                    concat_ws(
                        ' ',
                        stage_name,
                        first_name,
                        last_name,
                        type::text,
                        about,
                        description,
                        current_city_name,
                        specific_attributes::text
                    ) AS document,
                    jsonb_build_object(
                        'type', type::text,
                        'city', current_city_name,
                        'rating', rating,
                        'hourly_rate', hourly_rate
                    ) AS metadata
                FROM performers
            ),
            ranked AS (
                SELECT
                    source_id,
                    title,
                    document,
                    metadata,
                    ts_rank_cd(
                        to_tsvector('simple', coalesce(document, '')),
                        websearch_to_tsquery('simple', :question)
                    ) AS rank
                FROM docs
            )
            SELECT *
            FROM ranked
            WHERE rank > 0 OR document ILIKE :pattern
            ORDER BY rank DESC, title ASC
            LIMIT :limit
        """),
        {"question": question, "pattern": f"%{question}%", "limit": limit},
    ).mappings().all()
    seen = set()
    merged_rows = []
    for row in [*structured_rows, *rows]:
        source_id = row["source_id"]
        if source_id in seen:
            continue
        seen.add(source_id)
        merged_rows.append(row)
        if len(merged_rows) >= limit:
            break
    return [
        RagContext(
            source="performers",
            source_id=row["source_id"],
            title=row["title"] or "Performer",
            content=_trim(row["document"]),
            score=float(row["rank"] or 0),
            metadata=dict(row["metadata"] or {}),
        )
        for row in merged_rows
    ]


def _retrieve_chat_users(db: Session, question: str, limit: int) -> list[RagContext]:
    rows = db.execute(
        text("""
            WITH docs AS (
                SELECT
                    id::text AS source_id,
                    name AS title,
                    concat_ws(' ', name, email) AS document,
                    jsonb_build_object('email', email, 'provider', provider) AS metadata
                FROM chat_users
            ),
            ranked AS (
                SELECT
                    source_id,
                    title,
                    document,
                    metadata,
                    ts_rank_cd(
                        to_tsvector('simple', coalesce(document, '')),
                        websearch_to_tsquery('simple', :question)
                    ) AS rank
                FROM docs
            )
            SELECT *
            FROM ranked
            WHERE rank > 0 OR document ILIKE :pattern
            ORDER BY rank DESC, title ASC
            LIMIT :limit
        """),
        {"question": question, "pattern": f"%{question}%", "limit": limit},
    ).mappings().all()
    return [
        RagContext(
            source="chat_users",
            source_id=row["source_id"],
            title=row["title"] or "User",
            content=_trim(row["document"]),
            score=float(row["rank"] or 0),
            metadata=dict(row["metadata"] or {}),
        )
        for row in rows
    ]


def build_prompt(question: str, contexts: list[RagContext]) -> list[dict[str, str]]:
    context_text = "\n\n".join(
        f"[{idx}] {item.source}:{item.source_id} - {item.title}\n{item.content}"
        for idx, item in enumerate(contexts, start=1)
    )
    system = (
        "You are ShowE AI, the ShowDan assistant. Answer only from the provided database context. "
        "If performer records are provided, list the matching performers with useful fields from metadata. "
        "If the context is insufficient, say what is missing. Keep answers concise and cite sources like [1]."
    )
    user = f"Question: {question}\n\nDatabase context:\n{context_text or 'No matching context found.'}"
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def call_llama(messages: list[dict[str, str]]) -> tuple[str, bool]:
    try:
        response = requests.post(
            f"{OLLAMA_BASE_URL.rstrip('/')}/api/chat",
            json={"model": AIRAG_LLM_MODEL, "messages": messages, "stream": False},
            timeout=90,
        )
        response.raise_for_status()
        data = response.json()
        return data.get("message", {}).get("content", "").strip(), True
    except requests.RequestException:
        return "", False


def fallback_answer(question: str, contexts: list[RagContext]) -> str:
    if not contexts:
        return "I could not find matching ShowDan database context for that question."
    lines = [f"ShowE AI found {len(contexts)} relevant database result(s) for: {question}"]
    for idx, item in enumerate(contexts[:5], start=1):
        lines.append(f"[{idx}] {item.source} - {item.title}: {_trim(item.content, 220)}")
    return "\n".join(lines)


def save_conversation(
    db: Session,
    question: str,
    answer: str,
    model: str | None,
    contexts: list[RagContext],
) -> int:
    row_id = db.execute(
        text("""
            INSERT INTO airag_conversations (question, answer, model, contexts)
            VALUES (:question, :answer, :model, CAST(:contexts AS jsonb))
            RETURNING id
        """),
        {
            "question": question,
            "answer": answer,
            "model": model,
            "contexts": "[" + ",".join(item.model_dump_json() for item in contexts) + "]",
        },
    ).scalar_one()
    db.commit()
    return row_id


def list_conversations(db: Session, limit: int) -> list[dict[str, Any]]:
    return [
        dict(row._mapping)
        for row in db.execute(
            text("""
                SELECT id, question, answer, model, created_at
                FROM airag_conversations
                ORDER BY created_at DESC
                LIMIT :limit
            """),
            {"limit": limit},
        ).all()
    ]


def ollama_available() -> bool:
    try:
        response = requests.get(f"{OLLAMA_BASE_URL.rstrip('/')}/api/tags", timeout=3)
        return response.ok
    except requests.RequestException:
        return False


def _trim(value: str | None, length: int = 1200) -> str:
    text_value = " ".join((value or "").split())
    if len(text_value) <= length:
        return text_value
    return text_value[: length - 3] + "..."


def _extract_performer_filters(db: Session, question: str) -> dict[str, str]:
    normalized = question.lower().replace("-", "_")
    filters: dict[str, str] = {}
    performer_types = [
        row[0]
        for row in db.execute(
            text("SELECT DISTINCT type::text FROM performers ORDER BY type::text")
        ).all()
    ]
    for performer_type in performer_types:
        if performer_type.lower() in normalized or performer_type.lower().replace("_", " ") in normalized:
            filters["type"] = performer_type
            break

    cities = [
        row[0]
        for row in db.execute(
            text("SELECT DISTINCT current_city_name FROM performers WHERE current_city_name IS NOT NULL")
        ).all()
    ]
    for city in cities:
        city_text = city.lower()
        if re.search(rf"\b{re.escape(city_text)}\b", question.lower()):
            filters["city"] = city
            break

    return filters
