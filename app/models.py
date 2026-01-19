from sqlalchemy import (
    Boolean,
    Column,
    Integer,
    String,
    DateTime,
    Float,
    ForeignKey,
    Table,
    Text,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from .database import Base


# Many-to-many association table for notes and tags
note_tags = Table(
    "note_tags",
    Base.metadata,
    Column("note_id", Integer, ForeignKey("notes.id"), primary_key=True),
    Column("tag_id", Integer, ForeignKey("tags.id"), primary_key=True),
)


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    email = Column(String, unique=True, index=True)
    password_hash = Column(String)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    is_deleted = Column(Boolean, default=False)

    notes = relationship("Note", back_populates="user")
    tags = relationship("Tag", back_populates="user")


class Note(Base):
    __tablename__ = "notes"

    id = Column(Integer, primary_key=True, index=True)
    local_id = Column(String, index=True)  # UUID from client
    user_id = Column(Integer, ForeignKey("users.id"), index=True)
    title = Column(String, index=True)

    # Hybrid transcript storage
    transcript_inline = Column(Text, nullable=True)  # For small transcripts (<50KB)
    transcript_path = Column(String, nullable=True)  # For large transcripts (>=50KB)
    transcript_size = Column(Integer, default=0)
    transcript_checksum = Column(String, nullable=True)  # SHA256 for sync conflict detection
    transcript_preview = Column(String(500), nullable=True)  # First 500 chars for list views

    audio_path = Column(String, nullable=True)
    duration = Column(Float, default=0.0)  # Duration in seconds
    recorded_at = Column(DateTime(timezone=True))
    summary = Column(Text, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    is_deleted = Column(Boolean, default=False)

    user = relationship("User", back_populates="notes")
    tags = relationship("Tag", secondary=note_tags, back_populates="notes")
    exports = relationship("Export", back_populates="note")


class Tag(Base):
    __tablename__ = "tags"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), index=True)
    name = Column(String, index=True)
    color = Column(String, nullable=True)  # Hex color code
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    is_deleted = Column(Boolean, default=False)

    user = relationship("User", back_populates="tags")
    notes = relationship("Note", secondary=note_tags, back_populates="tags")


class Export(Base):
    __tablename__ = "exports"

    id = Column(Integer, primary_key=True, index=True)
    export_id = Column(String, unique=True, index=True)  # UUID for download URL
    note_id = Column(Integer, ForeignKey("notes.id"), index=True)
    format = Column(String)  # "pdf" or "markdown"
    file_path = Column(String)
    status = Column(String, default="pending")  # "pending", "completed", "failed"
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)

    note = relationship("Note", back_populates="exports")
