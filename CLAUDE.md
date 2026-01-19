# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoiceLog is a full-stack voice dictation app with AI post-processing. It has a FastAPI Python backend and a native Swift iOS app.

## Common Commands

### Backend

```bash
# Install dependencies
uv sync

# Run all tests
uv run pytest

# Run specific test
uv run pytest tests/test_notes.py::test_create_note

# Start backend server
python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### iOS App

```bash
# Full local dev environment (backend + simulator + app)
./scripts/local-dev.sh

# Build iOS app for simulator
xcodebuild -project VoiceLogApp/VoiceLogApp.xcodeproj -scheme VoiceLogApp \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug -derivedDataPath VoiceLogApp/build build

# Run E2E UI tests
./scripts/ios-ui-test.sh all

# Run specific UI test
./scripts/ios-ui-test.sh login
```

Build paths are centralized in `scripts/build-config.sh`.

## Architecture

### Backend (`app/`)

- **main.py** - FastAPI app with all REST endpoints
- **models.py** - SQLAlchemy ORM models (User, Note, Tag, Export)
- **schemas.py** - Pydantic request/response validation
- **crud.py** - Database operations
- **auth.py** - JWT authentication with refresh token rotation
- **services/** - Business logic:
  - `llm_service.py` - AI summarization (Anthropic/OpenAI/Ollama)
  - `storage_service.py` - Hybrid transcript storage (inline <50KB, file >=50KB)
  - `export_service.py` - PDF/Markdown generation

### iOS App (`VoiceLogApp/`)

- **Core/Networking/** - APIClient, APIEndpoint definitions
- **Core/Services/SpeechService.swift** - Voice recognition using SFSpeechRecognizer with automatic session restart at ~55s to handle Apple's 60s limit
- **Core/Sync/** - Bidirectional sync with server
- **Features/** - SwiftUI views organized by feature (Auth, Notes, Recording, Settings)

Uses MVVM pattern with SwiftData for local persistence.

### Database

SQLite with automatic migration via `create_db_and_tables()`. Transcripts use hybrid storage: inline for small (<50KB), file-based for large (>=50KB).

## Testing

Backend tests use pytest with in-memory SQLite. Fixtures in `tests/conftest.py` provide test client and pre-authenticated user.

iOS E2E tests use IDB (Instagram Debug Bridge) for UI automation. Requires running backend and booted simulator.

## Known Issues

See `TODO.md` for current blockers. Critical issue: iOS app cannot parse auth API responses due to format mismatch between backend response and iOS Codable models.
