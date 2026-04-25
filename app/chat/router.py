from datetime import datetime
from pathlib import Path
from uuid import uuid4
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, WebSocket, WebSocketDisconnect, status
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import ValidationError
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.chat.models import ChatConversation, ChatMessage
from app.chat.redis_manager import chat_manager
from app.chat.schemas import (
    ChatConversationResponse,
    ChatMessageResponse,
    ConversationCreate,
    MessageCreate,
    UserRef,
    UserResponse,
)
from app.db.database import SessionLocal, get_db
from app.models.chat_user import ChatUser

router = APIRouter(prefix="/chat", tags=["Chat"])
STATIC_DIR = Path(__file__).resolve().parent / "static"
UPLOAD_DIR = Path(__file__).resolve().parent / "uploads"
UPLOAD_DIR.mkdir(exist_ok=True)


def normalize_pair(first: UserRef, second: UserRef) -> tuple[UserRef, UserRef]:
    ordered = sorted([first, second], key=lambda user: str(user.id))
    return ordered[0], ordered[1]


def current_user_id(request: Request) -> UUID:
    user_id = request.session.get("chat_user_id")
    if not user_id:
        raise HTTPException(status_code=401, detail="Login with Google first")
    return UUID(user_id)


def get_user_or_404(db: Session, user_id: UUID) -> ChatUser:
    db_user = db.get(ChatUser, user_id)
    if not db_user:
        raise HTTPException(status_code=404, detail=f"User {user_id} not found")
    return db_user


def conversation_response(db: Session, conversation: ChatConversation) -> ChatConversationResponse:
    last_message = db.execute(
        select(ChatMessage)
        .where(ChatMessage.conversation_id == conversation.id)
        .order_by(ChatMessage.created_at.desc())
        .limit(1)
    ).scalar_one_or_none()
    response = ChatConversationResponse.model_validate(conversation)
    response.last_message = ChatMessageResponse.model_validate(last_message) if last_message else None
    return response


def create_message_record(db: Session, conversation_id: UUID, payload: MessageCreate) -> ChatMessageResponse:
    conversation = db.get(ChatConversation, conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")

    participant_ids = {conversation.user_a_id, conversation.user_b_id}
    if payload.sender_id not in participant_ids:
        raise HTTPException(status_code=403, detail="Sender is not a participant in this conversation")

    created_at = datetime.utcnow()
    message = ChatMessage(
        conversation_id=conversation_id,
        sender_id=payload.sender_id,
        body=payload.body.strip(),
        media_url=payload.media_url,
        media_type=payload.media_type,
        media_name=payload.media_name,
        created_at=created_at,
    )
    conversation.updated_at = created_at
    db.add(message)
    db.commit()
    db.refresh(message)
    return ChatMessageResponse.model_validate(message)


@router.get("/ui", response_class=HTMLResponse)
def chat_ui() -> HTMLResponse:
    with open(STATIC_DIR / "index.html", encoding="utf-8") as html_file:
        return HTMLResponse(html_file.read())


@router.get("/media/{filename}")
def get_media(filename: str):
    media_path = (UPLOAD_DIR / filename).resolve()
    if not str(media_path).startswith(str(UPLOAD_DIR.resolve())) or not media_path.exists():
        raise HTTPException(status_code=404, detail="Media not found")
    return FileResponse(media_path)


@router.get("/me", response_model=UserResponse)
def get_me(request: Request, db: Session = Depends(get_db)):
    return get_user_or_404(db, current_user_id(request))


@router.get("/users", response_model=list[UserResponse])
def list_users(request: Request, db: Session = Depends(get_db)):
    me = current_user_id(request)
    return db.execute(
        select(ChatUser)
        .where(ChatUser.id != me)
        .order_by(ChatUser.name)
    ).scalars().all()


@router.post("/conversations", response_model=ChatConversationResponse, status_code=status.HTTP_201_CREATED)
def create_or_get_conversation(
    payload: ConversationCreate,
    request: Request,
    db: Session = Depends(get_db),
):
    me = current_user_id(request)
    participant_ids = {payload.user_one.id, payload.user_two.id}
    if me not in participant_ids:
        raise HTTPException(status_code=403, detail="Conversation must include the logged-in user")
    if payload.user_one == payload.user_two:
        raise HTTPException(status_code=400, detail="A user cannot chat with themselves")

    get_user_or_404(db, payload.user_one.id)
    get_user_or_404(db, payload.user_two.id)

    user_a, user_b = normalize_pair(payload.user_one, payload.user_two)
    conversation = db.execute(
        select(ChatConversation).where(
            ChatConversation.user_a_id == user_a.id,
            ChatConversation.user_b_id == user_b.id,
        )
    ).scalar_one_or_none()

    if not conversation:
        conversation = ChatConversation(user_a_id=user_a.id, user_b_id=user_b.id)
        db.add(conversation)
        db.commit()
        db.refresh(conversation)

    return conversation_response(db, conversation)


@router.get("/conversations", response_model=list[ChatConversationResponse])
def list_conversations(request: Request, db: Session = Depends(get_db)):
    me = current_user_id(request)
    conversations = db.execute(
        select(ChatConversation)
        .where(or_(ChatConversation.user_a_id == me, ChatConversation.user_b_id == me))
        .order_by(ChatConversation.updated_at.desc())
    ).scalars().all()
    return [conversation_response(db, conversation) for conversation in conversations]


@router.get("/conversations/{conversation_id}/messages", response_model=list[ChatMessageResponse])
def list_messages(
    conversation_id: UUID,
    request: Request,
    limit: int = 50,
    db: Session = Depends(get_db),
):
    me = current_user_id(request)
    conversation = db.get(ChatConversation, conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if me not in {conversation.user_a_id, conversation.user_b_id}:
        raise HTTPException(status_code=403, detail="You are not a participant in this conversation")

    limit = max(1, min(limit, 200))
    messages = db.execute(
        select(ChatMessage)
        .where(ChatMessage.conversation_id == conversation_id)
        .order_by(ChatMessage.created_at.desc())
        .limit(limit)
    ).scalars().all()
    return list(reversed(messages))


@router.post("/conversations/{conversation_id}/messages", response_model=ChatMessageResponse, status_code=status.HTTP_201_CREATED)
async def send_message(
    conversation_id: UUID,
    payload: MessageCreate,
    request: Request,
    db: Session = Depends(get_db),
):
    me = current_user_id(request)
    if payload.sender_id != me:
        raise HTTPException(status_code=403, detail="Messages must be sent as the logged-in user")

    response_model = create_message_record(db, conversation_id, payload)
    response = response_model.model_dump(mode="json")
    await chat_manager.publish(conversation_id, {"event": "message.created", "message": response})
    return response_model


@router.post("/conversations/{conversation_id}/media", response_model=ChatMessageResponse, status_code=status.HTTP_201_CREATED)
async def send_media(
    conversation_id: UUID,
    request: Request,
    sender_id: UUID = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    me = current_user_id(request)
    if sender_id != me:
        raise HTTPException(status_code=403, detail="Media must be sent as the logged-in user")

    original_name = Path(file.filename or "upload").name
    suffix = Path(original_name).suffix
    stored_name = f"{uuid4().hex}{suffix}"
    stored_path = UPLOAD_DIR / stored_name
    contents = await file.read()
    if len(contents) > 20 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Media file is too large")
    stored_path.write_bytes(contents)

    payload = MessageCreate(
        sender_id=sender_id,
        body=original_name,
        media_url=f"/chat/media/{stored_name}",
        media_type=file.content_type,
        media_name=original_name,
    )
    response_model = create_message_record(db, conversation_id, payload)
    response = response_model.model_dump(mode="json")
    await chat_manager.publish(conversation_id, {"event": "message.created", "message": response})
    return response_model


@router.websocket("/ws/{conversation_id}")
async def websocket_chat(websocket: WebSocket, conversation_id: UUID):
    session_user_id = websocket.session.get("chat_user_id")
    if not session_user_id:
        await websocket.close(code=1008)
        return

    await chat_manager.connect(conversation_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            try:
                payload = MessageCreate.model_validate(data)
                if payload.sender_id != UUID(session_user_id):
                    await websocket.send_json({"event": "error", "detail": "Messages must be sent as the logged-in user"})
                    continue
                db = SessionLocal()
                try:
                    message = create_message_record(db, conversation_id, payload)
                finally:
                    db.close()
                await chat_manager.publish(
                    conversation_id,
                    {"event": "message.created", "message": message.model_dump(mode="json")},
                )
            except (HTTPException, ValidationError) as exc:
                detail = exc.detail if isinstance(exc, HTTPException) else exc.errors()
                await websocket.send_json({"event": "error", "detail": detail})
    except WebSocketDisconnect:
        await chat_manager.disconnect(conversation_id, websocket)
