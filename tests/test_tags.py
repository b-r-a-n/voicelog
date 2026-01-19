import pytest
from fastapi.testclient import TestClient


def test_create_tag(client: TestClient, auth_headers: dict):
    response = client.post(
        "/tags/",
        headers=auth_headers,
        json={"name": "Work", "color": "#FF5733"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Work"
    assert data["color"] == "#FF5733"


def test_list_tags(client: TestClient, auth_headers: dict):
    # Create some tags
    tags = ["Work", "Personal", "Ideas"]
    for tag in tags:
        client.post(
            "/tags/",
            headers=auth_headers,
            json={"name": tag}
        )

    response = client.get("/tags/", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 3


def test_update_tag(client: TestClient, auth_headers: dict):
    # Create tag
    create_response = client.post(
        "/tags/",
        headers=auth_headers,
        json={"name": "Original", "color": "#000000"}
    )
    tag_id = create_response.json()["id"]

    # Update tag
    response = client.put(
        f"/tags/{tag_id}",
        headers=auth_headers,
        json={"name": "Updated", "color": "#FFFFFF"}
    )
    assert response.status_code == 200
    assert response.json()["name"] == "Updated"
    assert response.json()["color"] == "#FFFFFF"


def test_delete_tag(client: TestClient, auth_headers: dict):
    # Create tag
    create_response = client.post(
        "/tags/",
        headers=auth_headers,
        json={"name": "ToDelete"}
    )
    tag_id = create_response.json()["id"]

    # Delete tag
    response = client.delete(f"/tags/{tag_id}", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["is_deleted"] == True


def test_add_tag_to_note(client: TestClient, auth_headers: dict):
    # Create note
    note_response = client.post(
        "/notes/",
        headers=auth_headers,
        json={"title": "Tagged Note", "transcript": "Content", "duration": 10.0}
    )
    note_id = note_response.json()["id"]

    # Create tag
    tag_response = client.post(
        "/tags/",
        headers=auth_headers,
        json={"name": "Important"}
    )
    tag_id = tag_response.json()["id"]

    # Add tag to note
    response = client.post(
        f"/notes/{note_id}/tags?tag_id={tag_id}",
        headers=auth_headers
    )
    assert response.status_code == 200
    tags = response.json()["tags"]
    assert len(tags) == 1
    assert tags[0]["name"] == "Important"


def test_remove_tag_from_note(client: TestClient, auth_headers: dict):
    # Create note
    note_response = client.post(
        "/notes/",
        headers=auth_headers,
        json={"title": "Tagged Note", "transcript": "Content", "duration": 10.0}
    )
    note_id = note_response.json()["id"]

    # Create and add tag
    tag_response = client.post(
        "/tags/",
        headers=auth_headers,
        json={"name": "ToRemove"}
    )
    tag_id = tag_response.json()["id"]

    client.post(f"/notes/{note_id}/tags?tag_id={tag_id}", headers=auth_headers)

    # Remove tag
    response = client.delete(
        f"/notes/{note_id}/tags/{tag_id}",
        headers=auth_headers
    )
    assert response.status_code == 200
    assert len(response.json()["tags"]) == 0
