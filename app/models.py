"""Схемы Launch Control."""
from __future__ import annotations

from pydantic import BaseModel


class Launch(BaseModel):
    id: str
    name: str
    rocket: str
    pad: str
    status: str          # "go" | "no-go"
    window_seconds: int   # длительность стартового окна


class CountdownResult(BaseModel):
    id: str
    status: str
    t_minus_seconds: int
