import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def test_health_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_health_reports_version(client):
    assert client.get("/health").json()["version"] == "1.0.0"


def test_list_has_five_missions(client):
    r = client.get("/api/v1/launches")
    assert r.status_code == 200
    assert len(r.json()) == 5


def test_list_contains_known_ids(client):
    ids = {item["id"] for item in client.get("/api/v1/launches").json()}
    assert {"LC-101", "LC-102", "LC-103", "LC-104", "LC-105"} == ids


def test_get_single_launch(client):
    r = client.get("/api/v1/launches/LC-101")
    assert r.status_code == 200
    assert r.json()["name"] == "Polaris-1"


def test_get_unknown_launch_is_404(client):
    assert client.get("/api/v1/launches/LC-999").status_code == 404


def test_countdown_go_returns_600(client):
    r = client.post("/api/v1/launches/LC-101/countdown")
    assert r.status_code == 200
    assert r.json()["t_minus_seconds"] == 600


def test_countdown_go_status_counting(client):
    assert client.post("/api/v1/launches/LC-101/countdown").json()["status"] == "counting"


def test_countdown_nogo_returns_409(client):
    assert client.post("/api/v1/launches/LC-102/countdown").status_code == 409


def test_countdown_unknown_is_404(client):
    assert client.post("/api/v1/launches/LC-999/countdown").status_code == 404


def test_countdown_other_go_launch(client):
    r = client.post("/api/v1/launches/LC-103/countdown")
    assert r.status_code == 200
    assert r.json()["t_minus_seconds"] == 1200


def test_list_each_has_required_fields(client):
    for item in client.get("/api/v1/launches").json():
        assert {"id", "name", "rocket", "pad", "status", "window_seconds"} <= set(item)
