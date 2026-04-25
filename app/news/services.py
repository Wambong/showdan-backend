import json
from pathlib import Path
from typing import Any

from fastapi import HTTPException, Request
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.elastic import es_client
from app.db.database import engine

PACKAGE_DIR = Path(__file__).resolve().parent.parent / "news_db_package"
NEWS_INDEX = "news"


def install_news_database() -> None:
    for filename in ("01_news_schema.sql", "02_news_procedures.sql"):
        sql = (PACKAGE_DIR / filename).read_text(encoding="utf-8")
        with engine.begin() as connection:
            connection.exec_driver_sql(sql)
    with engine.begin() as connection:
        connection.exec_driver_sql("""
            ALTER TABLE news ADD COLUMN IF NOT EXISTS date_created TIMESTAMP WITHOUT TIME ZONE;
            ALTER TABLE news ADD COLUMN IF NOT EXISTS date_updated TIMESTAMP WITHOUT TIME ZONE;
            UPDATE news
            SET
                date_created = COALESCE(date_created, created_at),
                date_updated = COALESCE(date_updated, updated_at)
            WHERE date_created IS NULL OR date_updated IS NULL;
            ALTER TABLE news ALTER COLUMN date_created SET DEFAULT CURRENT_TIMESTAMP;
            ALTER TABLE news ALTER COLUMN date_updated SET DEFAULT CURRENT_TIMESTAMP;
        """)


def ensure_news_index() -> None:
    mapping = json.loads((PACKAGE_DIR / "03_elasticsearch_index.json").read_text(encoding="utf-8"))
    if not es_client.indices.exists(index=NEWS_INDEX):
        es_client.indices.create(index=NEWS_INDEX, **mapping)


def rows_as_dicts(rows) -> list[dict[str, Any]]:
    return [with_news_dates(dict(row._mapping)) for row in rows]


def one_or_404(row, detail: str = "News item not found") -> dict[str, Any]:
    if row is None:
        raise HTTPException(status_code=404, detail=detail)
    return with_news_dates(dict(row._mapping))


def with_news_dates(row: dict[str, Any]) -> dict[str, Any]:
    if "created_at" in row and "date_created" not in row:
        row["date_created"] = row["created_at"]
    if "updated_at" in row and "date_updated" not in row:
        row["date_updated"] = row["updated_at"]
    return row


def session_user_name(request: Request, fallback: str | None = None) -> str:
    if fallback:
        return fallback
    user = request.session.get("user") or {}
    return user.get("name") or user.get("email") or "Anonymous"


def sync_news_queue_once(db: Session, limit: int = 100) -> dict[str, int]:
    rows = db.execute(
        text("SELECT * FROM select_elasticsearch_sync_queue(:limit)"),
        {"limit": limit},
    ).mappings().all()
    processed = 0
    failed = 0

    for row in rows:
        queue_id = row["id"]
        entity_id = row["entity_id"]
        action = row["action"]
        payload = row["payload"] or {}
        try:
            if action == "DELETE":
                es_client.options(ignore_status=[404]).delete(index=NEWS_INDEX, id=str(entity_id))
            else:
                doc = dict(payload)
                lat = doc.pop("lat", None)
                lng = doc.pop("lng", None)
                if lat is not None and lng is not None:
                    doc["location"] = {"lat": lat, "lon": lng}
                es_client.index(index=NEWS_INDEX, id=str(entity_id), document=doc)

            db.execute(
                text("SELECT mark_elasticsearch_sync_processed(:queue_id)"),
                {"queue_id": queue_id},
            )
            processed += 1
        except Exception as exc:
            db.execute(
                text("SELECT mark_elasticsearch_sync_failed(:queue_id, :error)"),
                {"queue_id": queue_id, "error": str(exc)},
            )
            failed += 1

    db.commit()
    return {"processed": processed, "failed": failed}
