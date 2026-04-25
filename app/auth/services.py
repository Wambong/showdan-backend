from authlib.integrations.starlette_client import OAuth
from app.core.config import settings

oauth = OAuth()

# Регистрация Google OAuth с параметрами из .env
oauth.register(
    name='google',
    server_metadata_url='https://accounts.google.com/.well-known/openid-configuration',
    client_id=settings.GOOGLE_CLIENT_ID,
    client_secret=settings.GOOGLE_CLIENT_SECRET,
    client_kwargs={'scope': 'openid email profile',
                   'redirect_uri': 'http://localhost:8000/auth/google/callback'},
)
