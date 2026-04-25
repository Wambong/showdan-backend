from pprint import pprint

from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import select, text
from geoalchemy2.elements import WKTElement
from uuid import UUID
from typing import List, Optional, Dict, Union
import logging

from app.db.database import get_db
from app.models.performer import Performer
from app.schemas.performer import PerformerCreate, PerformerUpdate, PerformerLongResponse, PerformerShortResponse
from app.core.elastic import es_client

router = APIRouter(prefix="/performers", tags=["Performers"])
logger = logging.getLogger(__name__)

# --- КЭШ СПРАВОЧНИКОВ ---
# Чтобы не делать JOIN-ы к словарям на каждый хит из Elastic, мы загрузим их в память
# (они редко меняются).
dictionaries_cache = {
    "languages": {},
    "genres": {},
    "event_categories": {}
}

def load_dictionaries(db: Session):
    """Загружает словари из БД в память при первом запросе"""
    if not dictionaries_cache["languages"]:
        # Предполагаем, что у вас есть таблицы dict_language, dict_genre и т.д.
        # Выполняем сырые запросы для примера (или через модели, если они есть)
        langs = db.execute(text("SELECT id, name FROM languages")).fetchall()
        dictionaries_cache["languages"] = {row.id: row.name for row in langs}

        genres = db.execute(text("SELECT id, name FROM genres")).fetchall()
        dictionaries_cache["genres"] = {row.id: row.name for row in genres}

        cats = db.execute(text("SELECT id, name FROM event_categories")).fetchall()
        dictionaries_cache["event_categories"] = {row.id: row.name for row in cats}
    return dictionaries_cache

def load_photo_urls(ids: List[str], db: Session):
    photo_urls_dict = {}
    for id in ids:
        photo_urls_dict[id] = db.execute(text(f"SELECT photo_url FROM performers WHERE id = '{id}'")).fetchone().photo_url
    return photo_urls_dict

def load_xp_points(ids: List[str], db: Session):
    photo_urls_dict = {}
    for id in ids:
        photo_urls_dict[id] = db.execute(
            text(f"SELECT xp_points FROM performers WHERE id = '{id}'")).fetchone().xp_points
    return photo_urls_dict

def enrich_es_hit(hit: dict, db: Session) -> dict:
    """Превращает сырой документ из ES в схему с названиями языков/жанров"""
    cache = load_dictionaries(db)

    # Базовые поля
    enriched = {**hit}

    # Извлекаем массивы ID из ES-документа
    comm_ids = hit.get("comm_language_ids", [])
    perf_ids = hit.get("perf_language_ids", [])
    genre_ids = hit.get("genre_ids", [])
    cat_ids = hit.get("event_category_ids", [])

    # Распаковываем ID в объекты {id: 1, name: "Russian"}
    enriched["comm_languages"] = [{"id": i, "name": cache["languages"].get(i, "Unknown")} for i in comm_ids]
    enriched["perf_languages"] = [{"id": i, "name": cache["languages"].get(i, "Unknown")} for i in perf_ids]
    enriched["genres"] = [{"id": i, "name": cache["genres"].get(i, "Unknown")} for i in genre_ids]
    enriched["event_categories"] = [{"id": i, "name": cache["event_categories"].get(i, "Unknown")} for i in cat_ids]

    return enriched

# --- ФОНОВЫЕ ЗАДАЧИ (оставляем без изменений) ---
def sync_to_es(doc_id: str, es_doc: dict):
    try:
        es_client.index(index="performers", id=doc_id, document=es_doc)
    except Exception as e:
        logger.error(f"ES Sync failed: {e}")

# --- ЭНДПОИНТЫ ---
@router.post("", response_model=PerformerLongResponse, status_code=201)
def create_performer(
    performer: PerformerCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    db_performer = Performer(
        type=performer.type,
        first_name=performer.first_name,
        last_name=performer.last_name,
        stage_name=performer.stage_name,
        photo_url=performer.photo_url,
        about=performer.about,
        description=performer.description,
        birth_date=performer.birth_date,
        experience_years=performer.experience_years,
        hourly_rate=performer.hourly_rate,
        current_city_name=performer.current_city_name,
        location_point=WKTElement(f"POINT({performer.lon} {performer.lat})", srid=4326),
        comm_language_ids=performer.comm_language_ids,
        perf_language_ids=performer.perf_language_ids,
        genre_ids=performer.genre_ids,
        event_category_ids=performer.event_category_ids,
        specific_attributes=performer.specific_attributes,
    )
    db.add(db_performer)
    db.commit()
    db.refresh(db_performer)

    es_doc = {
        "id": str(db_performer.id),
        "type": db_performer.type,
        "first_name": db_performer.first_name,
        "last_name": db_performer.last_name,
        "stage_name": db_performer.stage_name,
        "about": db_performer.about,
        "description": db_performer.description,
        "birth_date": db_performer.birth_date.isoformat(),
        "experience_years": db_performer.experience_years,
        "hourly_rate": float(db_performer.hourly_rate or 0),
        "rating": db_performer.rating,
        "current_city_name": db_performer.current_city_name,
        "comm_language_ids": db_performer.comm_language_ids or [],
        "perf_language_ids": db_performer.perf_language_ids or [],
        "genre_ids": db_performer.genre_ids or [],
        "event_category_ids": db_performer.event_category_ids or [],
        "specific_attributes": db_performer.specific_attributes or {},
    }
    background_tasks.add_task(sync_to_es, str(db_performer.id), es_doc)

    return {
        **es_doc,
        "id": db_performer.id,
        "photo_url": db_performer.photo_url,
        "xp_points": db_performer.xp_points,
        "current_level": db_performer.current_level,
        "comm_languages": [],
        "perf_languages": [],
        "genres": [],
        "event_categories": [],
    }


@router.get("/search", response_model=Union[List[PerformerLongResponse], List[PerformerShortResponse]])
def search_performers(
    q: Optional[str] = Query(None),
    city: Optional[str] = Query(None),
    type: Optional[str] = Query(None),
    genre_id: Optional[int] = Query(None),
    perf_language_id: Optional[int] = Query(None),
    short: Optional[bool] = True,
    db: Session = Depends(get_db)
):
    query_body = {"bool": {"must": [], "filter": []}}

    if q:
        query_body["bool"]["must"].append({
            "multi_match": {
                "query": q,
                "fields": ["stage_name^3", "first_name", "last_name", "about"],
                "fuzziness": "AUTO"
            }
        })
    else:
        query_body["bool"]["must"].append({"match_all": {}})

    if city:
        query_body["bool"]["filter"].append({"term": {"current_city_name.keyword": city}})
    if type:
        query_body["bool"]["filter"].append({"term": {"type": type}})
    if genre_id:
        query_body["bool"]["filter"].append({"term": {"genre_ids": genre_id}})
    if perf_language_id:
        query_body["bool"]["filter"].append({"term": {"perf_language_ids": perf_language_id}})

    try:
        # Ищем в Elasticsearch (получаем только массивы ID)
        response = es_client.search(index="performers", query=query_body, size=50)
        hits = response["hits"]["hits"]

        # Обогащаем каждый хит названиями из PostgreSQL
        results = [enrich_es_hit(hit["_source"], db) for hit in hits]
        if short:
            results = [
                {
                    "id": hit['id'],
                    "first_name": hit['first_name'],
                    "last_name": hit['last_name'],
                    "hourly_rate": hit['hourly_rate'],
                    "photo_url": load_photo_urls([hit['id']], db)[hit['id']],
                    "xp_points": load_xp_points([hit['id']], db)[hit['id']],
                    "rating": hit['rating']
                }
                for hit in results
            ]
        else:
            for hit in results:
                hit['xp_points'] = load_xp_points([hit['id']], db)[hit['id']]
        return results

    except Exception as e:
        raise e
        logger.error(f"Search failed: {e}")
        raise HTTPException(status_code=503, detail="Search service unavailable")

@router.get("/{performer_id}", response_model=PerformerLongResponse)
def get_performer(performer_id: UUID, db: Session = Depends(get_db)):
    # 1. Достаем исполнителя из БД
    stmt = select(Performer).where(Performer.id == performer_id)
    db_performer = db.execute(stmt).scalar_one_or_none()

    if not db_performer:
        raise HTTPException(status_code=404, detail="Performer not found")

    # 2. Превращаем ORM-модель в словарь
    performer_dict = {
        "id": db_performer.id,
        "type": db_performer.type,
        "first_name": db_performer.first_name,
        "last_name": db_performer.last_name,
        "stage_name": db_performer.stage_name,
        "about": db_performer.about,
        "current_city_name": db_performer.current_city_name,
        "hourly_rate": db_performer.hourly_rate,
        "rating": db_performer.rating,
        "experience_years": db_performer.experience_years,
        "birth_date": db_performer.birth_date,
        "xp_points": db_performer.xp_points,
        "current_level": db_performer.current_level,
        "comm_language_ids": db_performer.comm_language_ids,
        "perf_language_ids": db_performer.perf_language_ids,
        "genre_ids": db_performer.genre_ids,
        "event_category_ids": db_performer.event_category_ids,
        "specific_attributes": db_performer.specific_attributes
    }

    # 3. Обогащаем названиями через ту же функцию, что и для поиска!
    enriched = enrich_es_hit(performer_dict, db)
    return enriched
