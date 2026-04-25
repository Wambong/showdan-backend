from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.news.schemas import (
    ElasticsearchSyncResponse,
    IdResponse,
    NewsCommentCreate,
    NewsCommentResponse,
    NewsCommentUpdate,
    NewsCreate,
    NewsNearbyResponse,
    NewsReactionCreate,
    NewsReactionDelete,
    NewsReactionSummary,
    NewsResponse,
    NewsUpdate,
    StatusResponse,
)
from app.news.services import one_or_404, rows_as_dicts, session_user_name, sync_news_queue_once

router = APIRouter(prefix="/news", tags=["News"])
admin_router = APIRouter(prefix="/admin/elasticsearch", tags=["Admin"])


@router.post("", response_model=IdResponse, status_code=status.HTTP_201_CREATED)
def create_news(payload: NewsCreate, request: Request, db: Session = Depends(get_db)):
    news_id = db.execute(
        text("""
            SELECT insert_news(
                :title, :content, :summary, :author_name, :category,
                :lat, :lng, :location_name, :image_url, :source_url, :is_published
            )
        """),
        {
            **payload.model_dump(),
            "author_name": session_user_name(request, payload.author_name),
        },
    ).scalar_one()
    db.execute(
        text("""
            UPDATE news
            SET date_created = created_at, date_updated = updated_at
            WHERE id = :news_id
        """),
        {"news_id": news_id},
    )
    db.commit()
    return {"id": news_id}


@router.put("/{news_id}", response_model=StatusResponse)
def update_news(news_id: int, payload: NewsUpdate, db: Session = Depends(get_db)):
    ok = db.execute(
        text("""
            SELECT update_news(
                :news_id, :title, :content, :summary, :category,
                :lat, :lng, :location_name, :image_url, :source_url, :is_published
            )
        """),
        {"news_id": news_id, **payload.model_dump()},
    ).scalar_one()
    if ok:
        db.execute(
            text("""
                UPDATE news
                SET date_updated = updated_at
                WHERE id = :news_id
            """),
            {"news_id": news_id},
        )
    db.commit()
    if not ok:
        raise HTTPException(status_code=404, detail="News item not found")
    return {"ok": ok}


@router.delete("/{news_id}", response_model=StatusResponse)
def delete_news(news_id: int, db: Session = Depends(get_db)):
    ok = db.execute(text("SELECT delete_news(:news_id)"), {"news_id": news_id}).scalar_one()
    db.commit()
    if not ok:
        raise HTTPException(status_code=404, detail="News item not found")
    return {"ok": ok}


@router.get("", response_model=list[NewsResponse])
def list_news(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    only_published: bool = True,
    db: Session = Depends(get_db),
):
    rows = db.execute(
        text("SELECT * FROM select_news_with_stats(:limit, :offset, :only_published)"),
        {"limit": limit, "offset": offset, "only_published": only_published},
    ).all()
    return rows_as_dicts(rows)


@router.get("/nearby", response_model=list[NewsNearbyResponse])
def nearby_news(
    lat: float,
    lng: float,
    radius_meters: float = Query(10000, gt=0),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    rows = db.execute(
        text("SELECT * FROM select_news_nearby(:lat, :lng, :radius_meters, :limit, :offset)"),
        {
            "lat": lat,
            "lng": lng,
            "radius_meters": radius_meters,
            "limit": limit,
            "offset": offset,
        },
    ).all()
    return rows_as_dicts(rows)


@router.get("/{news_id}", response_model=NewsResponse)
def get_news(news_id: int, db: Session = Depends(get_db)):
    row = db.execute(text("SELECT * FROM select_news_by_id(:news_id)"), {"news_id": news_id}).first()
    return one_or_404(row)


@router.post("/{news_id}/comments", response_model=IdResponse, status_code=status.HTTP_201_CREATED)
def create_comment(news_id: int, payload: NewsCommentCreate, request: Request, db: Session = Depends(get_db)):
    parent_comment_id = payload.parent_comment_id or None
    try:
        comment_id = db.execute(
            text("SELECT insert_news_comment(:news_id, :user_name, :comment, :parent_comment_id)"),
            {
                "news_id": news_id,
                "user_name": session_user_name(request, payload.user_name),
                "comment": payload.comment,
                "parent_comment_id": parent_comment_id,
            },
        ).scalar_one()
        db.commit()
    except SQLAlchemyError as exc:
        db.rollback()
        message = str(getattr(exc, "orig", exc))
        if "Parent comment does not exist" in message:
            raise HTTPException(status_code=400, detail="parent_comment_id must be an existing comment id, or omit it for a top-level comment")
        raise
    return {"id": comment_id}


@router.get("/{news_id}/comments", response_model=list[NewsCommentResponse])
def list_comments(news_id: int, db: Session = Depends(get_db)):
    rows = db.execute(text("SELECT * FROM select_news_comments(:news_id)"), {"news_id": news_id}).all()
    return rows_as_dicts(rows)


@router.put("/comments/{comment_id}", response_model=StatusResponse)
def update_comment(comment_id: int, payload: NewsCommentUpdate, request: Request, db: Session = Depends(get_db)):
    ok = db.execute(
        text("SELECT update_news_comment(:comment_id, :user_name, :comment)"),
        {
            "comment_id": comment_id,
            "user_name": session_user_name(request, payload.user_name),
            "comment": payload.comment,
        },
    ).scalar_one()
    db.commit()
    if not ok:
        raise HTTPException(status_code=404, detail="Comment not found")
    return {"ok": ok}


@router.delete("/comments/{comment_id}", response_model=StatusResponse)
def delete_comment(
    comment_id: int,
    request: Request,
    user_name: str | None = None,
    db: Session = Depends(get_db),
):
    ok = db.execute(
        text("SELECT delete_news_comment(:comment_id, :user_name)"),
        {"comment_id": comment_id, "user_name": session_user_name(request, user_name)},
    ).scalar_one()
    db.commit()
    if not ok:
        raise HTTPException(status_code=404, detail="Comment not found")
    return {"ok": ok}


@router.post("/{news_id}/reactions", response_model=IdResponse, status_code=status.HTTP_201_CREATED)
def add_reaction(news_id: int, payload: NewsReactionCreate, request: Request, db: Session = Depends(get_db)):
    reaction_id = db.execute(
        text("SELECT add_news_reaction(:news_id, :user_name, :reaction_type, :emoji)"),
        {
            "news_id": news_id,
            "user_name": session_user_name(request, payload.user_name),
            "reaction_type": payload.reaction_type,
            "emoji": payload.emoji,
        },
    ).scalar_one()
    db.commit()
    return {"id": reaction_id}


@router.delete("/{news_id}/reactions", response_model=StatusResponse)
def remove_reaction(news_id: int, payload: NewsReactionDelete, request: Request, db: Session = Depends(get_db)):
    ok = db.execute(
        text("SELECT remove_news_reaction(:news_id, :user_name, :reaction_type, :emoji)"),
        {
            "news_id": news_id,
            "user_name": session_user_name(request, payload.user_name),
            "reaction_type": payload.reaction_type,
            "emoji": payload.emoji,
        },
    ).scalar_one()
    db.commit()
    if not ok:
        raise HTTPException(status_code=404, detail="Reaction not found")
    return {"ok": ok}


@router.get("/{news_id}/reactions", response_model=list[NewsReactionSummary])
def reactions_summary(news_id: int, db: Session = Depends(get_db)):
    rows = db.execute(text("SELECT * FROM select_news_reactions_summary(:news_id)"), {"news_id": news_id}).all()
    return rows_as_dicts(rows)


@admin_router.post("/sync-once", response_model=ElasticsearchSyncResponse)
def sync_once(limit: int = Query(100, ge=1, le=1000), db: Session = Depends(get_db)):
    return sync_news_queue_once(db, limit)
