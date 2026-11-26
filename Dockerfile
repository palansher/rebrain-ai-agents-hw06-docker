# Launch Control: multi-stage сборка.
# builder ставит зависимости по uv.lock; runtime получает только venv и код приложения.

# ---- build stage ----------------------------------------------------------
FROM python:3.12.16-slim-trixie@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b AS builder

# uv фиксированной версии, без pip и без установки пакетов в базовый слой.
COPY --from=ghcr.io/astral-sh/uv:0.13.8 /uv /usr/local/bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app

# Сначала только манифесты: правка app/ не инвалидирует слой с зависимостями.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

# ---- runtime stage --------------------------------------------------------
FROM python:3.12.16-slim-trixie@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv
COPY app ./app

# Приложение в ФС не пишет, поэтому /app остаётся read-only для пользователя.
RUN useradd --system --uid 10001 --no-create-home appuser
USER 10001:10001

EXPOSE 8000

# curl/wget в slim нет (и ставить их нельзя): healthcheck на stdlib Python.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
