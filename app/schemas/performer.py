from pydantic import BaseModel, ConfigDict, Field
from typing import List, Optional, Dict
from datetime import date
from uuid import UUID

class LanguageItem(BaseModel):
    id: int
    name: str

class GenreItem(BaseModel):
    id: int
    name: str

class CategoryItem(BaseModel):
    id: int
    name: str

class PerformerBase(BaseModel):
    type: str
    first_name: str
    last_name: str
    stage_name: str
    photo_url: Optional[str] = None
    about: Optional[str] = None
    description: Optional[str] = None
    # Сделали эти поля Optional, так как они не отдаются из ElasticSearch:
    birth_date: Optional[date] = None
    experience_years: int
    hourly_rate: float
    current_city_name: str
    specific_attributes: dict = Field(default_factory=dict)

class PerformerCreate(PerformerBase):
    birth_date: date  # При создании обязательно
    lat: float
    lon: float
    comm_language_ids: List[int] = Field(default_factory=list)
    perf_language_ids: List[int] = Field(default_factory=list)
    genre_ids: List[int] = Field(default_factory=list)
    event_category_ids: List[int] = Field(default_factory=list)

class PerformerUpdate(PerformerBase):
    lat: Optional[float] = None
    lon: Optional[float] = None
    comm_language_ids: Optional[List[int]] = None
    perf_language_ids: Optional[List[int]] = None
    genre_ids: Optional[List[int]] = None
    event_category_ids: Optional[List[int]] = None

class PerformerLongResponse(PerformerBase):
    id: UUID
    # Сделали эти поля Optional, так как они не отдаются из ElasticSearch:
    xp_points: Optional[int] = 0
    current_level: Optional[int] = 1
    rating: float
    photo_url: Optional[str] = None

    comm_languages: List[LanguageItem] = Field(default_factory=list)
    perf_languages: List[LanguageItem] = Field(default_factory=list)
    genres: List[GenreItem] = Field(default_factory=list)
    event_categories: List[CategoryItem] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)

class PerformerShortResponse(BaseModel):
    id: UUID
    first_name: str
    last_name: str
    xp_points: Optional[int] = 0
    rating: float
    photo_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)