from fastapi import APIRouter, Request, HTTPException
from starlette.responses import RedirectResponse
from sqlalchemy import select

from app.auth.services import oauth
import notificore_restapi as api

from app.core.config import settings
from app.db.database import SessionLocal
from app.models.chat_user import ChatUser

router = APIRouter()
sms_client = api.SMSAPI(config={'api_key': settings.NOTIFICORE_API_KEY})

@router.get("/google/login")
async def login(request: Request):
    """Перенаправление на страницу авторизации Google"""
    redirect_uri = request.url_for('auth_callback')

    return await oauth.google.authorize_redirect(request, redirect_uri)


@router.route('/google/callback')
async def auth_callback(request: Request):
    """Обработчик callback от Google"""
    try:
        # Пытаемся получить токен
        token = await oauth.google.authorize_access_token(request)

        # Получаем информацию о пользователе
        user_info = token.get('userinfo')

        request.session['user'] = user_info
        db = SessionLocal()
        try:
            provider_user_id = user_info.get("sub") or user_info.get("email")
            if not provider_user_id:
                raise HTTPException(status_code=400, detail="Google profile did not include a user id")

            chat_user = db.execute(
                select(ChatUser).where(ChatUser.provider_user_id == provider_user_id)
            ).scalar_one_or_none()
            if not chat_user:
                chat_user = ChatUser(provider_user_id=provider_user_id)
                db.add(chat_user)

            chat_user.email = user_info.get("email")
            chat_user.name = user_info.get("name") or user_info.get("email") or "Google user"
            chat_user.picture = user_info.get("picture")
            db.commit()
            db.refresh(chat_user)
            request.session['chat_user_id'] = str(chat_user.id)
        finally:
            db.close()

        return RedirectResponse(url='/chat/ui')

    except Exception as e:
        # Если пользователь уже авторизован, возможно, это повторный запрос
        if 'user' in request.session:
            # Логируем успешный вход

            return RedirectResponse(url='/chat/ui')


        raise HTTPException(status_code=400, detail=str(e))
