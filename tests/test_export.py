import pytest
from datetime import datetime, timedelta, timezone
from fastapi.testclient import TestClient


def create_note_with_transcript(client: TestClient, auth_headers: dict) -> int:
    """Helper to create a note with transcript for export testing."""
    response = client.post(
        "/notes/",
        headers=auth_headers,
        json={
            "title": "Test Export Note",
            "transcript": "This is a test transcript for export testing.",
            "duration": 60.0
        }
    )
    return response.json()["id"]


class TestExportNote:
    """Tests for POST /notes/{note_id}/export endpoint."""

    def test_export_to_pdf_returns_export_status(self, client: TestClient, auth_headers: dict):
        """Test that exporting to PDF returns ExportStatus with correct fields."""
        note_id = create_note_with_transcript(client, auth_headers)

        response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "pdf"}
        )

        assert response.status_code == 200
        data = response.json()
        assert "export_id" in data
        assert data["note_id"] == note_id
        assert data["format"] == "pdf"
        assert data["status"] == "completed"
        assert "created_at" in data
        assert "expires_at" in data

    def test_export_to_markdown_returns_export_status(self, client: TestClient, auth_headers: dict):
        """Test that exporting to Markdown returns ExportStatus with correct fields."""
        note_id = create_note_with_transcript(client, auth_headers)

        response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "markdown"}
        )

        assert response.status_code == 200
        data = response.json()
        assert "export_id" in data
        assert data["note_id"] == note_id
        assert data["format"] == "markdown"
        assert data["status"] == "completed"
        assert "created_at" in data
        assert "expires_at" in data

    def test_export_invalid_format(self, client: TestClient, auth_headers: dict):
        """Test that invalid export format returns 400."""
        note_id = create_note_with_transcript(client, auth_headers)

        response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "invalid"}
        )

        assert response.status_code == 400
        assert "Invalid export format" in response.json()["detail"]

    def test_export_note_not_found(self, client: TestClient, auth_headers: dict):
        """Test that exporting non-existent note returns 404."""
        response = client.post(
            "/notes/99999/export",
            headers=auth_headers,
            json={"format": "pdf"}
        )

        assert response.status_code == 404
        assert response.json()["detail"] == "Note not found"

    def test_export_deleted_note(self, client: TestClient, auth_headers: dict):
        """Test that exporting deleted note returns 404."""
        note_id = create_note_with_transcript(client, auth_headers)
        client.delete(f"/notes/{note_id}", headers=auth_headers)

        response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "pdf"}
        )

        assert response.status_code == 404
        assert response.json()["detail"] == "Note not found"

    def test_export_note_empty_transcript(self, client: TestClient, auth_headers: dict):
        """Test that exporting note with empty transcript returns 400."""
        # Create note without transcript
        create_response = client.post(
            "/notes/",
            headers=auth_headers,
            json={
                "title": "Note Without Transcript",
                "transcript": "",
                "duration": 0.0
            }
        )
        note_id = create_response.json()["id"]

        response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "pdf"}
        )

        assert response.status_code == 400
        assert "no transcript" in response.json()["detail"].lower()

    def test_export_requires_auth(self, client: TestClient, auth_headers: dict):
        """Test that export endpoint requires authentication."""
        note_id = create_note_with_transcript(client, auth_headers)

        response = client.post(
            f"/notes/{note_id}/export",
            json={"format": "pdf"}
        )

        assert response.status_code == 401


class TestDownloadExport:
    """Tests for GET /export/{export_id} endpoint."""

    def test_download_pdf_file(self, client: TestClient, auth_headers: dict):
        """Test downloading PDF export returns correct content-type."""
        note_id = create_note_with_transcript(client, auth_headers)

        # Create export
        export_response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "pdf"}
        )
        export_id = export_response.json()["export_id"]

        # Download export
        response = client.get(
            f"/export/{export_id}",
            headers=auth_headers
        )

        assert response.status_code == 200
        assert response.headers["content-type"] == "application/pdf"

    def test_download_markdown_file(self, client: TestClient, auth_headers: dict):
        """Test downloading Markdown export returns correct content-type."""
        note_id = create_note_with_transcript(client, auth_headers)

        # Create export
        export_response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "markdown"}
        )
        export_id = export_response.json()["export_id"]

        # Download export
        response = client.get(
            f"/export/{export_id}",
            headers=auth_headers
        )

        assert response.status_code == 200
        assert "text/markdown" in response.headers["content-type"]

    def test_download_markdown_contains_content(self, client: TestClient, auth_headers: dict):
        """Test that downloaded Markdown contains expected content."""
        note_id = create_note_with_transcript(client, auth_headers)

        # Create export
        export_response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "markdown"}
        )
        export_id = export_response.json()["export_id"]

        # Download export
        response = client.get(
            f"/export/{export_id}",
            headers=auth_headers
        )

        content = response.text
        assert "# Test Export Note" in content
        assert "## Transcript" in content
        assert "This is a test transcript for export testing." in content

    def test_download_export_not_found(self, client: TestClient, auth_headers: dict):
        """Test downloading non-existent export returns 404."""
        response = client.get(
            "/export/nonexistent-export-id",
            headers=auth_headers
        )

        assert response.status_code == 404
        assert response.json()["detail"] == "Export not found"

    def test_download_requires_auth(self, client: TestClient, auth_headers: dict):
        """Test that download endpoint requires authentication."""
        note_id = create_note_with_transcript(client, auth_headers)

        # Create export
        export_response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "pdf"}
        )
        export_id = export_response.json()["export_id"]

        # Try to download without auth
        response = client.get(f"/export/{export_id}")

        assert response.status_code == 401

    def test_download_other_user_export(self, client: TestClient, auth_headers: dict):
        """Test that user cannot download another user's export."""
        note_id = create_note_with_transcript(client, auth_headers)

        # Create export as first user
        export_response = client.post(
            f"/notes/{note_id}/export",
            headers=auth_headers,
            json={"format": "pdf"}
        )
        export_id = export_response.json()["export_id"]

        # Register second user
        client.post(
            "/auth/register",
            json={"name": "Other User", "email": "other@example.com", "password": "password123"}
        )
        login_response = client.post(
            "/auth/login",
            data={"username": "other@example.com", "password": "password123"}
        )
        other_headers = {"Authorization": f"Bearer {login_response.json()['access_token']}"}

        # Try to download as second user
        response = client.get(
            f"/export/{export_id}",
            headers=other_headers
        )

        assert response.status_code == 404
        assert response.json()["detail"] == "Export not found"
