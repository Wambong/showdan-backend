import time
import logging

from fastapi import FastAPI
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from starlette.middleware.cors import CORSMiddleware
from starlette.middleware.sessions import SessionMiddleware

from app.AIRAG.router import router as airag_router
from app.AIRAG.services import install_airag_database
from app.api.routers import performers
from app.chat import models as chat_models
from app.chat.redis_manager import chat_manager
from app.chat.router import router as chat_router
from app.core.config import settings
from app.auth.router import router as auth_router
from app.db.database import Base, engine
from app.models.chat_user import ChatUser
from app.news.router import admin_router as news_admin_router
from app.news.router import router as news_router
from app.news.services import install_news_database

app = FastAPI(title=settings.PROJECT_NAME)
logger = logging.getLogger(__name__)

# Добавляем middleware для сессий
app.add_middleware(
    SessionMiddleware,
    secret_key=settings.SECRET_KEY,
    same_site='lax',  # или 'strict' для повышенной безопасности
    https_only=False  # True для продакшена с HTTPS
)

# Настройка CORS с использованием параметров из .env
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Добавляем роутеры
app.include_router(auth_router, prefix="/auth", tags=["auth"])
app.include_router(performers.router)
app.include_router(chat_router)
app.include_router(news_router)
app.include_router(news_admin_router)
app.include_router(airag_router)


@app.on_event("startup")
def create_chat_tables():
    for attempt in range(1, 31):
        try:
            with engine.begin() as connection:
                connection.execute(text("""
                    DO $$
                    DECLARE
                        conversation_count integer := 0;
                        message_count integer := 0;
                        has_old_conversation_columns boolean := false;
                        has_old_message_columns boolean := false;
                    BEGIN
                        SELECT EXISTS (
                            SELECT 1
                            FROM information_schema.columns
                            WHERE table_name = 'chat_conversations'
                              AND column_name IN ('performer_a_id', 'performer_a_type', 'performer_b_id', 'performer_b_type')
                        ) INTO has_old_conversation_columns;

                        IF has_old_conversation_columns THEN
                            EXECUTE 'SELECT count(*) FROM chat_conversations' INTO conversation_count;
                            IF conversation_count = 0 THEN
                                DROP TABLE IF EXISTS chat_messages;
                                DROP TABLE IF EXISTS chat_conversations;
                            END IF;
                        END IF;

                        SELECT EXISTS (
                            SELECT 1
                            FROM information_schema.columns
                            WHERE table_name = 'chat_messages'
                              AND column_name = 'sender_type'
                        ) INTO has_old_message_columns;

                        IF has_old_message_columns THEN
                            EXECUTE 'SELECT count(*) FROM chat_messages' INTO message_count;
                            IF message_count = 0 THEN
                                DROP TABLE IF EXISTS chat_messages;
                            END IF;
                        END IF;

                        SELECT EXISTS (
                            SELECT 1
                            FROM information_schema.columns
                            WHERE table_name = 'chat_conversations'
                              AND column_name = 'user_a_id'
                        ) INTO has_old_conversation_columns;

                        IF EXISTS (
                            SELECT 1
                            FROM information_schema.tables
                            WHERE table_name = 'chat_conversations'
                        ) AND NOT has_old_conversation_columns THEN
                            EXECUTE 'SELECT count(*) FROM chat_conversations' INTO conversation_count;
                            IF conversation_count = 0 THEN
                                DROP TABLE IF EXISTS chat_messages;
                                DROP TABLE IF EXISTS chat_conversations;
                            END IF;
                        END IF;

                        IF EXISTS (
                            SELECT 1
                            FROM information_schema.constraint_column_usage
                            WHERE table_name = 'clients'
                              AND constraint_name IN (
                                  SELECT constraint_name
                                  FROM information_schema.table_constraints
                                  WHERE table_name = 'chat_conversations'
                                    AND constraint_type = 'FOREIGN KEY'
                              )
                        ) THEN
                            EXECUTE 'SELECT count(*) FROM chat_conversations' INTO conversation_count;
                            IF conversation_count = 0 THEN
                                DROP TABLE IF EXISTS chat_messages;
                                DROP TABLE IF EXISTS chat_conversations;
                            END IF;
                        END IF;

                        SELECT EXISTS (
                            SELECT 1
                            FROM information_schema.columns
                            WHERE table_name = 'chat_messages'
                              AND column_name = 'sender_id'
                        ) INTO has_old_message_columns;

                        IF EXISTS (
                            SELECT 1
                            FROM information_schema.tables
                            WHERE table_name = 'chat_messages'
                        ) AND NOT has_old_message_columns THEN
                            EXECUTE 'SELECT count(*) FROM chat_messages' INTO message_count;
                            IF message_count = 0 THEN
                                DROP TABLE IF EXISTS chat_messages;
                            END IF;
                        END IF;

                        IF EXISTS (
                            SELECT 1
                            FROM information_schema.tables
                            WHERE table_name = 'chat_messages'
                        ) THEN
                            ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS media_url varchar(500);
                            ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS media_type varchar(100);
                            ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS media_name varchar(255);
                        END IF;
                    END $$;
                """))
            Base.metadata.create_all(bind=engine, tables=[
                ChatUser.__table__,
                chat_models.ChatConversation.__table__,
                chat_models.ChatMessage.__table__,
            ])
            install_news_database()
            install_airag_database()
            return
        except OperationalError:
            if attempt == 30:
                raise
            time.sleep(2)


@app.on_event("shutdown")
async def close_chat_resources():
    await chat_manager.close()
