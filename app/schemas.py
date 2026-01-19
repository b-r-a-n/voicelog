from pydantic import BaseModel, ConfigDict, EmailStr
from datetime import datetime
from typing import List, Optional


# Auth schemas
class UserRegister(BaseModel):
    name: str
    email: EmailStr
    password: str


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


# User schemas
class UserBase(BaseModel):
    name: str
    email: EmailStr


class User(UserBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime


# Tag schemas
class TagBase(BaseModel):
    name: str
    color: Optional[str] = None


class TagCreate(TagBase):
    pass


class TagUpdate(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None


class Tag(TagBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    created_at: datetime
    updated_at: datetime
    is_deleted: bool = False


# Note schemas
class NoteBase(BaseModel):
    title: str
    local_id: Optional[str] = None


class NoteCreate(NoteBase):
    transcript: Optional[str] = None
    transcript_checksum: Optional[str] = None
    duration: float = 0.0
    recorded_at: Optional[datetime] = None


class NoteUpdate(BaseModel):
    title: Optional[str] = None
    transcript: Optional[str] = None
    transcript_checksum: Optional[str] = None


class NoteListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    local_id: Optional[str] = None
    title: str
    transcript_preview: Optional[str] = None
    transcript_size: int
    transcript_checksum: Optional[str] = None
    duration: float
    recorded_at: Optional[datetime] = None
    summary: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    is_deleted: bool = False
    tags: List[Tag] = []


class NoteDetail(NoteListItem):
    transcript: Optional[str] = None  # Full transcript content


class NoteSummarize(BaseModel):
    prompt: Optional[str] = None  # Custom prompt for summarization


class NoteExport(BaseModel):
    format: str  # "pdf" or "markdown"


# Export schemas
class ExportStatus(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    export_id: str
    note_id: int
    format: str
    status: str
    created_at: datetime
    expires_at: Optional[datetime] = None


# Sync schemas
class SyncRequest(BaseModel):
    since: Optional[datetime] = None


class NoteSync(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    local_id: Optional[str] = None
    title: str
    transcript_preview: Optional[str] = None
    transcript_size: int
    transcript_checksum: Optional[str] = None
    duration: float
    recorded_at: Optional[datetime] = None
    summary: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    is_deleted: bool = False
    tag_ids: List[int] = []


class TagSync(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    color: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    is_deleted: bool = False


class SyncResponse(BaseModel):
    notes: List[NoteSync] = []
    tags: List[TagSync] = []
    sync_timestamp: datetime


class NoteChunkUpload(BaseModel):
    local_id: str
    chunk_index: int
    total_chunks: int
    data: str  # Base64 encoded chunk
    checksum: str  # Final checksum (only verified on last chunk)


class NoteChunkResponse(BaseModel):
    received_chunks: int
    total_chunks: int
    complete: bool
    note_id: Optional[int] = None  # Set when upload is complete


# Client sync payload
class ClientNoteChange(BaseModel):
    local_id: str
    title: str
    transcript: Optional[str] = None
    transcript_checksum: Optional[str] = None
    transcript_preview: Optional[str] = None
    duration: float = 0.0
    recorded_at: Optional[datetime] = None
    is_deleted: bool = False
    tag_ids: List[int] = []


class ClientTagChange(BaseModel):
    local_id: Optional[str] = None
    server_id: Optional[int] = None
    name: str
    color: Optional[str] = None
    is_deleted: bool = False


class SyncPush(BaseModel):
    since: Optional[datetime] = None
    notes: List[ClientNoteChange] = []
    tags: List[ClientTagChange] = []
