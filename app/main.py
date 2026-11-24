"""HTTP-слой Launch Control - учебный API управления запусками ракет."""
from __future__ import annotations

from fastapi import FastAPI, HTTPException

from app import __version__
from app.catalog import BY_ID, LAUNCHES
from app.models import CountdownResult, Launch

app = FastAPI(title="Launch Control", version=__version__)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "version": __version__}


@app.get("/api/v1/launches")
def list_launches() -> list[Launch]:
    return LAUNCHES


@app.get("/api/v1/launches/{launch_id}")
def get_launch(launch_id: str) -> Launch:
    launch = BY_ID.get(launch_id)
    if launch is None:
        raise HTTPException(status_code=404, detail=f"unknown launch: {launch_id}")
    return launch


@app.post("/api/v1/launches/{launch_id}/countdown", response_model=CountdownResult)
def start_countdown(launch_id: str) -> CountdownResult:
    launch = BY_ID.get(launch_id)
    if launch is None:
        raise HTTPException(status_code=404, detail=f"unknown launch: {launch_id}")
    if launch.status != "go":
        # no-go: окно закрыто (погода и т.п.)
        raise HTTPException(status_code=409, detail=f"launch {launch_id} is no-go")
    return CountdownResult(id=launch.id, status="counting", t_minus_seconds=launch.window_seconds)
