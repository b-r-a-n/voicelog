import pytest
from datetime import datetime, timezone
from fastapi.testclient import TestClient


def test_sync_full(client: TestClient, auth_headers: dict):
    # Create some notes
    for i in range(2):
        client.post(
            "/notes/",
            headers=auth_headers,
            json={
                "title": f"Note {i}",
                "local_id": f"local-{i}",
                "transcript": f"Transcript {i}",
                "duration": 30.0
            }
        )

    # Create a tag
    client.post(
        "/tags/",
        headers=auth_headers,
        json={"name": "TestTag"}
    )

    # Full sync (since=None)
    response = client.post(
        "/sync",
        headers=auth_headers,
        json={"since": None, "notes": [], "tags": []}
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data["notes"]) == 2
    assert len(data["tags"]) == 1
    assert "sync_timestamp" in data


def test_sync_delta(client: TestClient, auth_headers: dict):
    # Create initial note
    client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "Initial Note",
            "local_id": "initial",
            "transcript": "Initial transcript",
            "duration": 20.0
        }
    )

    # Get sync timestamp - use a past time to ensure new note is included
    from datetime import timedelta
    past_time = (datetime.now(timezone.utc) - timedelta(seconds=1)).isoformat()

    # Create another note
    client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "New Note",
            "local_id": "new",
            "transcript": "New transcript",
            "duration": 25.0
        }
    )

    # Delta sync with past timestamp should include the new note
    response = client.post(
        "/sync",
        headers=auth_headers,
        json={"since": past_time, "notes": [], "tags": []}
    )
    assert response.status_code == 200
    data = response.json()
    # Should get notes updated after past_time
    assert len(data["notes"]) >= 1
    new_notes = [n for n in data["notes"] if n["local_id"] == "new"]
    assert len(new_notes) == 1


def test_sync_push_notes(client: TestClient, auth_headers: dict):
    # Push a new note from client
    response = client.post(
        "/sync",
        headers=auth_headers,
        json={
            "since": None,
            "notes": [
                {
                    "local_id": "client-note-1",
                    "title": "Client Note",
                    "transcript": "Created on client",
                    "transcript_checksum": "abc123",
                    "transcript_preview": "Created on client",
                    "duration": 45.0,
                    "recorded_at": datetime.now(timezone.utc).isoformat(),
                    "is_deleted": False,
                    "tag_ids": []
                }
            ],
            "tags": []
        }
    )
    assert response.status_code == 200

    # Verify note was created
    list_response = client.get("/notes/", headers=auth_headers)
    notes = list_response.json()
    client_notes = [n for n in notes if n["local_id"] == "client-note-1"]
    assert len(client_notes) == 1
    assert client_notes[0]["title"] == "Client Note"


def test_sync_deleted_notes(client: TestClient, auth_headers: dict):
    # Create and delete a note
    create_response = client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "To Delete",
            "local_id": "delete-me",
            "transcript": "Will be deleted",
            "duration": 10.0
        }
    )
    note_id = create_response.json()["id"]
    client.delete(f"/notes/{note_id}", headers=auth_headers)

    # Sync should include deleted note with is_deleted flag
    response = client.post(
        "/sync",
        headers=auth_headers,
        json={"since": None, "notes": [], "tags": []}
    )
    assert response.status_code == 200
    data = response.json()
    deleted_notes = [n for n in data["notes"] if n["local_id"] == "delete-me"]
    assert len(deleted_notes) == 1
    assert deleted_notes[0]["is_deleted"] == True
