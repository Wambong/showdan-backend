from pathlib import Path

from pydantic_settings import BaseSettings
from typing import List

class Settings(BaseSettings):
    # Основные настройки
    PROJECT_NAME: str = "ShowDan API"
    SECRET_KEY: str
    DEBUG: bool = False

    # Google OAuth
    GOOGLE_CLIENT_ID: str
    GOOGLE_CLIENT_SECRET: str

    # JWT
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"

    # CORS
    BACKEND_CORS_ORIGINS: List[str] = []

    # NOTIFICORE_API_KEY
    NOTIFICORE_API_KEY: str

    class Config:
        env_file=str(Path(__file__).resolve().parent / ".env"),
        case_sensitive = False

settings = Settings()
