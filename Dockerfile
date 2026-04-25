FROM python:3.12-slim-bookworm

RUN sed -i -e 's|deb.debian.org|mirror.yandex.ru|g' /etc/apt/sources.list.d/debian.sources
RUN apt update

RUN apt install -y --no-install-recommends git-core

ADD . /opt/showdan-backend
WORKDIR /opt/showdan-backend

RUN pip install uv
RUN cd /opt/showdan-backend && uv pip install --system --upgrade setuptools && uv pip install --system -r requirements.txt && uv pip install --system git+https://github.com/Notificore/notificore-python --no-build-isolation

CMD ["fastapi", "dev", "--port", "8000", "--host", "0.0.0.0","/opt/showdan-backend/app/main.py"]
