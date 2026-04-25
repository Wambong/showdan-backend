from sqlalchemy import Column, String, Integer, Float, Date, Numeric
from sqlalchemy.dialects.postgresql import UUID, JSONB, ARRAY
from geoalchemy2 import Geometry
import uuid
from app.db.database import Base

class Performer(Base):
    __tablename__ = "performers"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    type = Column(String, primary_key=True)
    first_name = Column(String, nullable=False)
    last_name = Column(String, nullable=False)
    stage_name = Column(String, nullable=False)
    photo_url = Column(String)
    about = Column(String)
    description = Column(String)
    birth_date = Column(Date, nullable=False)
    experience_years = Column(Integer, nullable=False)
    xp_points = Column(Integer, default=0)
    current_level = Column(Integer, default=1)
    hourly_rate = Column(Numeric(10, 2))
    rating = Column(Float, default=0.0)
    current_city_name = Column(String)
    location_point = Column(Geometry('POINT', srid=4326))
    comm_language_ids = Column(ARRAY(Integer), default=list)
    perf_language_ids = Column(ARRAY(Integer), default=list)
    genre_ids = Column(ARRAY(Integer), default=list)
    event_category_ids = Column(ARRAY(Integer), default=list)
    specific_attributes = Column(JSONB, default=dict)
