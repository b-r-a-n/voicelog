import os
from datetime import datetime, timezone
from typing import List

from fastapi import Depends, FastAPI, HTTPException, status, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from contextlib import asynccontextmanager

from . import crud, models, schemas
from .database import create_db_and_tables, get_db
from .auth import (
    get_current_user,
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    verify_refresh_token,
)
from .services.storage_service import storage_service
from .services.llm_service import llm_service
from .services.export_service import export_service


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield


app = FastAPI(title="VoiceLog API", lifespan=lifespan)

# CORS middleware
cors_origins = os.getenv("CORS_ORIGINS", "http://localhost:5173,http://localhost:3000")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in cors_origins.split(",")],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============ Auth Endpoints ============

@app.post("/auth/register", response_model=schemas.User)
def register(user: schemas.UserRegister, db: Session = Depends(get_db)):
    """Register a new user account."""
    existing_user = crud.get_user_by_email(db, email=user.email)
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    password_hash = get_password_hash(user.password)
    db_user = crud.create_user(db, user, password_hash)
    return db_user


@app.post("/auth/login", response_model=schemas.Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """Login and receive access and refresh tokens."""
    user = crud.get_user_by_email(db, email=form_data.username)
    if not user or not user.password_hash:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not verify_password(form_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return {
        "access_token": create_access_token(user.id),
        "refresh_token": create_refresh_token(user.id),
        "token_type": "bearer"
    }


@app.post("/auth/refresh", response_model=schemas.Token)
def refresh_tokens(body: schemas.RefreshRequest, db: Session = Depends(get_db)):
    """Get new access and refresh tokens using a valid refresh token."""
    user_id = verify_refresh_token(body.refresh_token)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user = crud.get_user(db, user_id=user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return {
        "access_token": create_access_token(user.id),
        "refresh_token": create_refresh_token(user.id),
        "token_type": "bearer"
    }


@app.get("/auth/me", response_model=schemas.User)
def get_me(current_user: models.User = Depends(get_current_user)):
    """Get current authenticated user info."""
    return current_user


# ============ Notes Endpoints ============

@app.post("/notes/", response_model=schemas.NoteListItem)
def create_note(
    note: schemas.NoteCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Create a new note."""
    transcript_inline = None
    transcript_path = None
    transcript_preview = None
    transcript_size = 0

    if note.transcript:
        transcript_inline, transcript_path, transcript_preview, transcript_size = \
            storage_service.store_transcript(current_user.id, 0, note.transcript)

    db_note = crud.create_note(
        db,
        user_id=current_user.id,
        note=note,
        transcript_inline=transcript_inline,
        transcript_path=transcript_path,
        transcript_preview=transcript_preview,
        transcript_size=transcript_size,
    )

    # If we stored to file, update with correct note ID
    if transcript_path and note.transcript:
        transcript_inline, transcript_path, transcript_preview, transcript_size = \
            storage_service.store_transcript(current_user.id, db_note.id, note.transcript)
        crud.update_note(
            db,
            db_note.id,
            schemas.NoteUpdate(),
            transcript_path=transcript_path,
        )
        db.refresh(db_note)

    return db_note


@app.get("/notes/", response_model=List[schemas.NoteListItem])
def list_notes(
    skip: int = 0,
    limit: int = 100,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """List all notes for the current user."""
    return crud.get_notes(db, user_id=current_user.id, skip=skip, limit=limit)


@app.get("/notes/{note_id}", response_model=schemas.NoteDetail)
def get_note(
    note_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get a note with full transcript."""
    db_note = crud.get_note(db, note_id=note_id)
    if db_note is None or db_note.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Note not found")
    if db_note.is_deleted:
        raise HTTPException(status_code=404, detail="Note not found")

    transcript = storage_service.get_transcript(
        db_note.transcript_inline,
        db_note.transcript_path,
    )

    return schemas.NoteDetail(
        id=db_note.id,
        local_id=db_note.local_id,
        title=db_note.title,
        transcript=transcript,
        transcript_preview=db_note.transcript_preview,
        transcript_size=db_note.transcript_size,
        transcript_checksum=db_note.transcript_checksum,
        duration=db_note.duration,
        recorded_at=db_note.recorded_at,
        summary=db_note.summary,
        created_at=db_note.created_at,
        updated_at=db_note.updated_at,
        tags=[schemas.Tag.model_validate(t) for t in db_note.tags],
    )


@app.put("/notes/{note_id}", response_model=schemas.NoteListItem)
def update_note(
    note_id: int,
    note_update: schemas.NoteUpdate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Update a note."""
    db_note = crud.get_note(db, note_id=note_id)
    if db_note is None or db_note.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Note not found")
    if db_note.is_deleted:
        raise HTTPException(status_code=404, detail="Note not found")

    transcript_inline = None
    transcript_path = None
    transcript_preview = None
    transcript_size = None

    if note_update.transcript is not None:
        transcript_inline, transcript_path, transcript_preview, transcript_size = \
            storage_service.update_transcript(
                current_user.id,
                note_id,
                note_update.transcript,
                db_note.transcript_path,
            )

    updated = crud.update_note(
        db,
        note_id=note_id,
        note_update=note_update,
        transcript_inline=transcript_inline,
        transcript_path=transcript_path,
        transcript_preview=transcript_preview,
        transcript_size=transcript_size,
    )
    return updated


@app.delete("/notes/{note_id}", response_model=schemas.NoteListItem)
def delete_note(
    note_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Soft delete a note."""
    db_note = crud.get_note(db, note_id=note_id)
    if db_note is None or db_note.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Note not found")

    return crud.delete_note(db, note_id=note_id)


@app.post("/notes/{note_id}/summarize", response_model=schemas.NoteDetail)
async def summarize_note(
    note_id: int,
    body: schemas.NoteSummarize,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Generate AI summary for a note."""
    db_note = crud.get_note(db, note_id=note_id)
    if db_note is None or db_note.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Note not found")
    if db_note.is_deleted:
        raise HTTPException(status_code=404, detail="Note not found")

    transcript = storage_service.get_transcript(
        db_note.transcript_inline,
        db_note.transcript_path,
    )

    if not transcript:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Note has no transcript to summarize"
        )

    try:
        summary = await llm_service.summarize(transcript, body.prompt)
        crud.update_note_summary(db, note_id, summary)
        db.refresh(db_note)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate summary: {str(e)}"
        )

    return schemas.NoteDetail(
        id=db_note.id,
        local_id=db_note.local_id,
        title=db_note.title,
        transcript=transcript,
        transcript_preview=db_note.transcript_preview,
        transcript_size=db_note.transcript_size,
        transcript_checksum=db_note.transcript_checksum,
        duration=db_note.duration,
        recorded_at=db_note.recorded_at,
        summary=db_note.summary,
        created_at=db_note.created_at,
        updated_at=db_note.updated_at,
        tags=[schemas.Tag.model_validate(t) for t in db_note.tags],
    )


@app.post("/notes/{note_id}/export", response_model=schemas.ExportStatus)
def export_note(
    note_id: int,
    body: schemas.NoteExport,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Export a note to PDF or Markdown."""
    db_note = crud.get_note(db, note_id=note_id)
    if db_note is None or db_note.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Note not found")
    if db_note.is_deleted:
        raise HTTPException(status_code=404, detail="Note not found")

    transcript = storage_service.get_transcript(
        db_note.transcript_inline,
        db_note.transcript_path,
    )

    if not transcript:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Note has no transcript to export"
        )

    tag_names = [t.name for t in db_note.tags]

    if body.format == "pdf":
        export_id, file_path = export_service.export_to_pdf(
            title=db_note.title,
            transcript=transcript,
            summary=db_note.summary,
            recorded_at=db_note.recorded_at,
            tags=tag_names,
        )
    elif body.format == "markdown":
        export_id, file_path = export_service.export_to_markdown(
            title=db_note.title,
            transcript=transcript,
            summary=db_note.summary,
            recorded_at=db_note.recorded_at,
            tags=tag_names,
        )
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid export format. Use 'pdf' or 'markdown'"
        )

    expires_at = export_service.get_expiry_time()
    db_export = crud.create_export(
        db,
        export_id=export_id,
        note_id=note_id,
        format=body.format,
        file_path=file_path,
        expires_at=expires_at,
    )
    crud.update_export_status(db, export_id, "completed")

    return schemas.ExportStatus(
        export_id=export_id,
        note_id=note_id,
        format=body.format,
        status="completed",
        created_at=db_export.created_at,
        expires_at=expires_at,
    )


# ============ Tags Endpoints ============

@app.post("/tags/", response_model=schemas.Tag)
def create_tag(
    tag: schemas.TagCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Create a new tag."""
    return crud.create_tag(db, user_id=current_user.id, tag=tag)


@app.get("/tags/", response_model=List[schemas.Tag])
def list_tags(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """List all tags for the current user."""
    return crud.get_tags(db, user_id=current_user.id)


@app.put("/tags/{tag_id}", response_model=schemas.Tag)
def update_tag(
    tag_id: int,
    tag_update: schemas.TagUpdate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Update a tag."""
    db_tag = crud.get_tag(db, tag_id=tag_id)
    if db_tag is None or db_tag.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Tag not found")
    if db_tag.is_deleted:
        raise HTTPException(status_code=404, detail="Tag not found")

    return crud.update_tag(db, tag_id=tag_id, tag_update=tag_update)


@app.delete("/tags/{tag_id}", response_model=schemas.Tag)
def delete_tag(
    tag_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Soft delete a tag."""
    db_tag = crud.get_tag(db, tag_id=tag_id)
    if db_tag is None or db_tag.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Tag not found")

    return crud.delete_tag(db, tag_id=tag_id)


@app.post("/notes/{note_id}/tags", response_model=schemas.NoteListItem)
def add_tag_to_note(
    note_id: int,
    tag_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Add a tag to a note."""
    db_note = crud.get_note(db, note_id=note_id)
    if db_note is None or db_note.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Note not found")

    db_tag = crud.get_tag(db, tag_id=tag_id)
    if db_tag is None or db_tag.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Tag not found")

    crud.add_tag_to_note(db, note_id=note_id, tag_id=tag_id)
    db.refresh(db_note)
    return db_note


@app.delete("/notes/{note_id}/tags/{tag_id}", response_model=schemas.NoteListItem)
def remove_tag_from_note(
    note_id: int,
    tag_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Remove a tag from a note."""
    db_note = crud.get_note(db, note_id=note_id)
    if db_note is None or db_note.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Note not found")

    crud.remove_tag_from_note(db, note_id=note_id, tag_id=tag_id)
    db.refresh(db_note)
    return db_note


# ============ Sync Endpoints ============

@app.post("/sync", response_model=schemas.SyncResponse)
def sync_data(
    sync_request: schemas.SyncPush,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Delta sync endpoint. Client sends changes, server returns changes since last sync."""
    since = sync_request.since
    if since is not None and since.tzinfo is not None:
        since = since.replace(tzinfo=None)

    sync_timestamp = datetime.now(timezone.utc)

    # Process client note changes
    for note_change in sync_request.notes:
        existing = crud.get_note_by_local_id(db, current_user.id, note_change.local_id)

        if existing:
            # Update existing note
            if note_change.is_deleted:
                crud.delete_note(db, existing.id)
            else:
                transcript_inline = None
                transcript_path = None
                transcript_preview = note_change.transcript_preview
                transcript_size = None

                if note_change.transcript:
                    transcript_inline, transcript_path, transcript_preview, transcript_size = \
                        storage_service.update_transcript(
                            current_user.id,
                            existing.id,
                            note_change.transcript,
                            existing.transcript_path,
                        )

                crud.update_note(
                    db,
                    existing.id,
                    schemas.NoteUpdate(
                        title=note_change.title,
                        transcript_checksum=note_change.transcript_checksum,
                    ),
                    transcript_inline=transcript_inline,
                    transcript_path=transcript_path,
                    transcript_preview=transcript_preview,
                    transcript_size=transcript_size,
                )
                if note_change.tag_ids:
                    crud.set_note_tags(db, existing.id, note_change.tag_ids)
        else:
            # Create new note
            if not note_change.is_deleted:
                transcript_inline = None
                transcript_path = None
                transcript_preview = note_change.transcript_preview
                transcript_size = 0

                new_note = crud.create_note(
                    db,
                    user_id=current_user.id,
                    note=schemas.NoteCreate(
                        title=note_change.title,
                        local_id=note_change.local_id,
                        transcript_checksum=note_change.transcript_checksum,
                        duration=note_change.duration,
                        recorded_at=note_change.recorded_at,
                    ),
                    transcript_inline=transcript_inline,
                    transcript_path=transcript_path,
                    transcript_preview=transcript_preview,
                    transcript_size=transcript_size,
                )

                if note_change.transcript:
                    transcript_inline, transcript_path, transcript_preview, transcript_size = \
                        storage_service.store_transcript(
                            current_user.id,
                            new_note.id,
                            note_change.transcript,
                        )
                    crud.update_note(
                        db,
                        new_note.id,
                        schemas.NoteUpdate(),
                        transcript_inline=transcript_inline,
                        transcript_path=transcript_path,
                        transcript_preview=transcript_preview,
                        transcript_size=transcript_size,
                    )

                if note_change.tag_ids:
                    crud.set_note_tags(db, new_note.id, note_change.tag_ids)

    # Process client tag changes
    for tag_change in sync_request.tags:
        if tag_change.server_id:
            existing = crud.get_tag(db, tag_change.server_id)
            if existing and existing.user_id == current_user.id:
                if tag_change.is_deleted:
                    crud.delete_tag(db, existing.id)
                else:
                    crud.update_tag(
                        db,
                        existing.id,
                        schemas.TagUpdate(name=tag_change.name, color=tag_change.color),
                    )
        else:
            if not tag_change.is_deleted:
                crud.create_tag(
                    db,
                    user_id=current_user.id,
                    tag=schemas.TagCreate(name=tag_change.name, color=tag_change.color),
                )

    # Get server changes since last sync
    notes = crud.get_notes_since(db, current_user.id, since)
    tags = crud.get_tags_since(db, current_user.id, since)

    return schemas.SyncResponse(
        notes=[
            schemas.NoteSync(
                id=n.id,
                local_id=n.local_id,
                title=n.title,
                transcript_preview=n.transcript_preview,
                transcript_size=n.transcript_size,
                transcript_checksum=n.transcript_checksum,
                duration=n.duration,
                recorded_at=n.recorded_at,
                summary=n.summary,
                created_at=n.created_at,
                updated_at=n.updated_at,
                is_deleted=n.is_deleted,
                tag_ids=[t.id for t in n.tags],
            )
            for n in notes
        ],
        tags=[
            schemas.TagSync(
                id=t.id,
                name=t.name,
                color=t.color,
                created_at=t.created_at,
                updated_at=t.updated_at,
                is_deleted=t.is_deleted,
            )
            for t in tags
        ],
        sync_timestamp=sync_timestamp,
    )


@app.post("/sync/notes/{local_id}/chunk", response_model=schemas.NoteChunkResponse)
def upload_note_chunk(
    local_id: str,
    chunk: schemas.NoteChunkUpload,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Upload a chunk of a large transcript. For transcripts > 500KB."""
    # This is a simplified implementation - in production you'd want
    # to store chunks temporarily and assemble them
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Chunked upload not yet implemented"
    )


# ============ Export Download ============

@app.get("/export/{export_id}")
def download_export(
    export_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Download an exported file."""
    db_export = crud.get_export(db, export_id)
    if db_export is None:
        raise HTTPException(status_code=404, detail="Export not found")

    # Verify the export belongs to the current user
    db_note = crud.get_note(db, db_export.note_id)
    if db_note is None or db_note.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Export not found")

    if db_export.status != "completed":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Export is not ready (status: {db_export.status})"
        )

    # Check expiry
    if db_export.expires_at and datetime.now(timezone.utc) > db_export.expires_at.replace(tzinfo=timezone.utc):
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="Export has expired"
        )

    file_path = export_service.get_export_path(export_id, db_export.format)
    if file_path is None:
        raise HTTPException(status_code=404, detail="Export file not found")

    media_type = "application/pdf" if db_export.format == "pdf" else "text/markdown"
    filename = f"{db_note.title}.{db_export.format}" if db_export.format == "pdf" else f"{db_note.title}.md"

    return FileResponse(
        path=file_path,
        media_type=media_type,
        filename=filename,
    )


# ============ Health Check ============

@app.get("/")
def read_root():
    return {"status": "ok", "app": "VoiceLog API"}
