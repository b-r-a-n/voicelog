import pytest
from unittest.mock import AsyncMock, patch
from fastapi.testclient import TestClient


def test_create_note(client: TestClient, auth_headers: dict):
    response = client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "Test Note",
            "local_id": "test-local-id",
            "transcript": "This is a test transcript.",
            "duration": 60.0
        }
    )
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "Test Note"
    assert data["local_id"] == "test-local-id"
    assert data["duration"] == 60.0


def test_list_notes(client: TestClient, auth_headers: dict):
    # Create some notes
    for i in range(3):
        client.post(
            "/notes/",
            headers=auth_headers,
            json={
                "title": f"Note {i}",
                "transcript": f"Transcript {i}",
                "duration": 30.0
            }
        )

    response = client.get("/notes/", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 3


def test_get_note(client: TestClient, auth_headers: dict):
    # Create note
    create_response = client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "Test Note",
            "transcript": "Full transcript content here.",
            "duration": 45.0
        }
    )
    note_id = create_response.json()["id"]

    # Get note
    response = client.get(f"/notes/{note_id}", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "Test Note"
    assert data["transcript"] == "Full transcript content here."


def test_update_note(client: TestClient, auth_headers: dict):
    # Create note
    create_response = client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "Original Title",
            "transcript": "Original transcript.",
            "duration": 30.0
        }
    )
    note_id = create_response.json()["id"]

    # Update note
    response = client.put(
        f"/notes/{note_id}",
        headers=auth_headers,
        json={"title": "Updated Title"}
    )
    assert response.status_code == 200
    assert response.json()["title"] == "Updated Title"


def test_delete_note(client: TestClient, auth_headers: dict):
    # Create note
    create_response = client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "Note to Delete",
            "transcript": "Will be deleted.",
            "duration": 15.0
        }
    )
    note_id = create_response.json()["id"]

    # Delete note
    response = client.delete(f"/notes/{note_id}", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["is_deleted"] == True

    # Verify it's gone from list
    list_response = client.get("/notes/", headers=auth_headers)
    note_ids = [n["id"] for n in list_response.json()]
    assert note_id not in note_ids


def test_note_unauthorized(client: TestClient):
    response = client.get("/notes/")
    assert response.status_code == 401


def test_note_not_found(client: TestClient, auth_headers: dict):
    response = client.get("/notes/99999", headers=auth_headers)
    assert response.status_code == 404


def test_summarize_note_success(client: TestClient, auth_headers: dict):
    """Test successful note summarization with mocked LLM."""
    # Create a note with transcript
    create_response = client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "Test Note for Summary",
            "transcript": "This is a test transcript that should be summarized.",
            "duration": 60.0
        }
    )
    note_id = create_response.json()["id"]

    # Mock the LLM service to return a fixed summary
    with patch("app.services.llm_service.llm_service.summarize", new_callable=AsyncMock) as mock_summarize:
        mock_summarize.return_value = "This is a mock summary of the transcript."

        response = client.post(
            f"/notes/{note_id}/summarize",
            headers=auth_headers,
            json={}
        )

        assert response.status_code == 200
        data = response.json()
        assert data["summary"] == "This is a mock summary of the transcript."
        assert data["id"] == note_id
        mock_summarize.assert_called_once()


def test_summarize_note_empty_transcript(client: TestClient, auth_headers: dict):
    """Test summarization fails with empty transcript."""
    # Create a note with empty transcript
    create_response = client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "Note with No Transcript",
            "transcript": "",
            "duration": 0.0
        }
    )
    note_id = create_response.json()["id"]

    response = client.post(
        f"/notes/{note_id}/summarize",
        headers=auth_headers,
        json={}
    )

    assert response.status_code == 400
    assert "no transcript" in response.json()["detail"].lower()


def test_summarize_note_not_found(client: TestClient, auth_headers: dict):
    """Test summarization fails with non-existent note ID."""
    response = client.post(
        "/notes/99999/summarize",
        headers=auth_headers,
        json={}
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Note not found"


def test_summarize_note_deleted(client: TestClient, auth_headers: dict):
    """Test summarization fails for deleted note."""
    # Create a note
    create_response = client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "Note to Delete",
            "transcript": "This note will be deleted.",
            "duration": 30.0
        }
    )
    note_id = create_response.json()["id"]

    # Delete the note
    client.delete(f"/notes/{note_id}", headers=auth_headers)

    # Try to summarize the deleted note
    response = client.post(
        f"/notes/{note_id}/summarize",
        headers=auth_headers,
        json={}
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Note not found"
