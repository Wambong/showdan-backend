import asyncio
import json
import os
from collections import defaultdict
from uuid import UUID

from fastapi import WebSocket
from redis.asyncio import Redis


REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")


class RedisChatManager:
    def __init__(self):
        self.redis = Redis.from_url(REDIS_URL, decode_responses=True)
        self.active_connections: dict[str, set[WebSocket]] = defaultdict(set)
        self.listener_tasks: dict[str, asyncio.Task] = {}

    def channel_name(self, conversation_id: UUID | str) -> str:
        return f"chat:conversation:{conversation_id}"

    async def connect(self, conversation_id: UUID, websocket: WebSocket) -> None:
        await websocket.accept()
        channel = self.channel_name(conversation_id)
        self.active_connections[channel].add(websocket)
        if channel not in self.listener_tasks or self.listener_tasks[channel].done():
            self.listener_tasks[channel] = asyncio.create_task(self._listen(channel))

    async def disconnect(self, conversation_id: UUID, websocket: WebSocket) -> None:
        channel = self.channel_name(conversation_id)
        connections = self.active_connections.get(channel)
        if not connections:
            return
        connections.discard(websocket)
        if not connections:
            task = self.listener_tasks.pop(channel, None)
            if task:
                task.cancel()
            self.active_connections.pop(channel, None)

    async def publish(self, conversation_id: UUID, payload: dict) -> None:
        await self.redis.publish(self.channel_name(conversation_id), json.dumps(payload, default=str))

    async def close(self) -> None:
        for task in self.listener_tasks.values():
            task.cancel()
        self.listener_tasks.clear()
        self.active_connections.clear()
        await self.redis.aclose()

    async def _listen(self, channel: str) -> None:
        pubsub = self.redis.pubsub()
        await pubsub.subscribe(channel)
        try:
            async for message in pubsub.listen():
                if message.get("type") != "message":
                    continue
                await self._broadcast(channel, message["data"])
        except asyncio.CancelledError:
            pass
        finally:
            await pubsub.unsubscribe(channel)
            await pubsub.aclose()

    async def _broadcast(self, channel: str, message: str) -> None:
        stale = []
        for websocket in list(self.active_connections.get(channel, set())):
            try:
                await websocket.send_text(message)
            except RuntimeError:
                stale.append(websocket)
        for websocket in stale:
            self.active_connections[channel].discard(websocket)


chat_manager = RedisChatManager()
