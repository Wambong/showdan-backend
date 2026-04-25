import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# URL базы данных PostgreSQL (с поддержкой PostGIS)
# Формат: postgresql://user:password@host:port/dbname
DATABASE_URL = os.getenv(
    "DATABASE_URL", 
    "postgresql://showdan:XkVMBg5Ik7vEW1hq8Orb@localhost:5432/postgres"
)

# Создаем движок SQLAlchemy
engine = create_engine(DATABASE_URL, echo=False)

# Создаем фабрику сессий
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Базовый класс для моделей
Base = declarative_base()

# ПОЛНАЯ РЕАЛИЗАЦИЯ зависимости get_db
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
