"""Статический каталог запусков (учебные данные)."""
from __future__ import annotations

from app.models import Launch

# Пять миссий. LC-101 - штатный запуск (go), LC-102 - no-go по погоде.
LAUNCHES: list[Launch] = [
    Launch(id="LC-101", name="Polaris-1", rocket="Falcon-9", pad="LC-39A", status="go", window_seconds=600),
    Launch(id="LC-102", name="Vega-Weather", rocket="Atlas-V", pad="SLC-41", status="no-go", window_seconds=900),
    Launch(id="LC-103", name="Helios-2", rocket="Ariane-6", pad="ELA-4", status="go", window_seconds=1200),
    Launch(id="LC-104", name="Orion-Test", rocket="New-Glenn", pad="LC-36", status="go", window_seconds=1800),
    Launch(id="LC-105", name="Lyra-3", rocket="Electron", pad="LC-1", status="go", window_seconds=300),
]

BY_ID: dict[str, Launch] = {launch.id: launch for launch in LAUNCHES}
