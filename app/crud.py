from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy.orm import Session

from . import models, schemas


# User CRUD
def get_user(db: Session, user_id: int) -> Optional[models.User]:
    return db.query(models.User).filter(models.User.id == user_id).first()


def get_user_by_email(db: Session, email: str) -> Optional[models.User]:
    return db.query(models.User).filter(models.User.email == email).first()


def create_user(db: Session, user: schemas.UserRegister, password_hash: str) -> models.User:
    db_user = models.User(
        name=user.name,
        email=user.email,
        password_hash=password_hash,
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user


# Note CRUD
def create_note(
    db: Session,
    user_id: int,
    note: schemas.NoteCreate,
    transcript_inline: Optional[str] = None,
    transcript_path: Optional[str] = None,
    transcript_preview: Optional[str] = None,
    transcript_size: int = 0,
) -> models.Note:
    db_note = models.Note(
        user_id=user_id,
        local_id=note.local_id,
        title=note.title,
        transcript_inline=transcript_inline,
        transcript_path=transcript_path,
        transcript_size=transcript_size,
        transcript_checksum=note.transcript_checksum,
        transcript_preview=transcript_preview,
        duration=note.duration,
        recorded_at=note.recorded_at or datetime.now(timezone.utc),
    )
    db.add(db_note)
    db.commit()
    db.refresh(db_note)
    return db_note


def get_note(db: Session, note_id: int) -> Optional[models.Note]:
    return db.query(models.Note).filter(models.Note.id == note_id).first()


def get_note_by_local_id(db: Session, user_id: int, local_id: str) -> Optional[models.Note]:
    return db.query(models.Note).filter(
        models.Note.user_id == user_id,
        models.Note.local_id == local_id
    ).first()


def get_notes(
    db: Session,
    user_id: int,
    skip: int = 0,
    limit: int = 100,
    include_deleted: bool = False
) -> List[models.Note]:
    query = db.query(models.Note).filter(models.Note.user_id == user_id)
    if not include_deleted:
        query = query.filter(models.Note.is_deleted == False)
    return query.order_by(models.Note.recorded_at.desc()).offset(skip).limit(limit).all()


def update_note(
    db: Session,
    note_id: int,
    note_update: schemas.NoteUpdate,
    transcript_inline: Optional[str] = None,
    transcript_path: Optional[str] = None,
    transcript_preview: Optional[str] = None,
    transcript_size: Optional[int] = None,
) -> Optional[models.Note]:
    db_note = get_note(db, note_id)
    if db_note is None:
        return None

    if note_update.title is not None:
        db_note.title = note_update.title
    if note_update.transcript_checksum is not None:
        db_note.transcript_checksum = note_update.transcript_checksum
    if transcript_inline is not None:
        db_note.transcript_inline = transcript_inline
        db_note.transcript_path = None
    if transcript_path is not None:
        db_note.transcript_path = transcript_path
        db_note.transcript_inline = None
    if transcript_preview is not None:
        db_note.transcript_preview = transcript_preview
    if transcript_size is not None:
        db_note.transcript_size = transcript_size

    db.commit()
    db.refresh(db_note)
    return db_note


def delete_note(db: Session, note_id: int) -> Optional[models.Note]:
    db_note = get_note(db, note_id)
    if db_note is None:
        return None
    db_note.is_deleted = True
    db.commit()
    db.refresh(db_note)
    return db_note


def update_note_summary(db: Session, note_id: int, summary: str) -> Optional[models.Note]:
    db_note = get_note(db, note_id)
    if db_note is None:
        return None
    db_note.summary = summary
    db.commit()
    db.refresh(db_note)
    return db_note


# Tag CRUD
def create_tag(db: Session, user_id: int, tag: schemas.TagCreate) -> models.Tag:
    db_tag = models.Tag(
        user_id=user_id,
        name=tag.name,
        color=tag.color,
    )
    db.add(db_tag)
    db.commit()
    db.refresh(db_tag)
    return db_tag


def get_tag(db: Session, tag_id: int) -> Optional[models.Tag]:
    return db.query(models.Tag).filter(models.Tag.id == tag_id).first()


def get_tags(
    db: Session,
    user_id: int,
    include_deleted: bool = False
) -> List[models.Tag]:
    query = db.query(models.Tag).filter(models.Tag.user_id == user_id)
    if not include_deleted:
        query = query.filter(models.Tag.is_deleted == False)
    return query.order_by(models.Tag.name).all()


def update_tag(db: Session, tag_id: int, tag_update: schemas.TagUpdate) -> Optional[models.Tag]:
    db_tag = get_tag(db, tag_id)
    if db_tag is None:
        return None

    if tag_update.name is not None:
        db_tag.name = tag_update.name
    if tag_update.color is not None:
        db_tag.color = tag_update.color

    db.commit()
    db.refresh(db_tag)
    return db_tag


def delete_tag(db: Session, tag_id: int) -> Optional[models.Tag]:
    db_tag = get_tag(db, tag_id)
    if db_tag is None:
        return None
    db_tag.is_deleted = True
    db.commit()
    db.refresh(db_tag)
    return db_tag


# Note-Tag associations
def add_tag_to_note(db: Session, note_id: int, tag_id: int) -> bool:
    note = get_note(db, note_id)
    tag = get_tag(db, tag_id)
    if note is None or tag is None:
        return False
    if tag not in note.tags:
        note.tags.append(tag)
        db.commit()
    return True


def remove_tag_from_note(db: Session, note_id: int, tag_id: int) -> bool:
    note = get_note(db, note_id)
    tag = get_tag(db, tag_id)
    if note is None or tag is None:
        return False
    if tag in note.tags:
        note.tags.remove(tag)
        db.commit()
    return True


def set_note_tags(db: Session, note_id: int, tag_ids: List[int]) -> bool:
    note = get_note(db, note_id)
    if note is None:
        return False
    tags = db.query(models.Tag).filter(models.Tag.id.in_(tag_ids)).all()
    note.tags = tags
    db.commit()
    return True


# Export CRUD
def create_export(
    db: Session,
    export_id: str,
    note_id: int,
    format: str,
    file_path: str,
    expires_at: Optional[datetime] = None,
) -> models.Export:
    db_export = models.Export(
        export_id=export_id,
        note_id=note_id,
        format=format,
        file_path=file_path,
        status="pending",
        expires_at=expires_at,
    )
    db.add(db_export)
    db.commit()
    db.refresh(db_export)
    return db_export


def get_export(db: Session, export_id: str) -> Optional[models.Export]:
    return db.query(models.Export).filter(models.Export.export_id == export_id).first()


def update_export_status(db: Session, export_id: str, status: str) -> Optional[models.Export]:
    db_export = get_export(db, export_id)
    if db_export is None:
        return None
    db_export.status = status
    db.commit()
    db.refresh(db_export)
    return db_export


# Sync queries
def get_notes_since(
    db: Session,
    user_id: int,
    since: Optional[datetime] = None
) -> List[models.Note]:
    query = db.query(models.Note).filter(models.Note.user_id == user_id)
    if since is not None:
        # Normalize to naive UTC
        if since.tzinfo is not None:
            since = since.replace(tzinfo=None)
        query = query.filter(models.Note.updated_at > since)
    return query.all()


def get_tags_since(
    db: Session,
    user_id: int,
    since: Optional[datetime] = None
) -> List[models.Tag]:
    query = db.query(models.Tag).filter(models.Tag.user_id == user_id)
    if since is not None:
        if since.tzinfo is not None:
            since = since.replace(tzinfo=None)
        query = query.filter(models.Tag.updated_at > since)
    return query.all()
