"""Офлайн-аналитика по истории запусков. НЕ часть сервиса - запускается вручную.

Импортирует pandas и numpy. Именно поэтому они лежат в основных зависимостях,
хотя рантайму сервиса (app/) не нужны: это и есть дефект, который студент должен
найти, сверив pyproject.toml с реальными импортами app/.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from app.catalog import LAUNCHES


def window_stats() -> pd.DataFrame:
    frame = pd.DataFrame([launch.model_dump() for launch in LAUNCHES])
    frame["window_minutes"] = np.round(frame["window_seconds"] / 60.0, 1)
    return frame.groupby("status")["window_minutes"].describe()


if __name__ == "__main__":
    print(window_stats())
