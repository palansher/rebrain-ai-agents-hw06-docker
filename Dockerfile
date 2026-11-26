# Так этот сервис упакован сегодня.
# Образ собирается, тесты внутри проходят, сервис работает - поэтому файл не трогали три релиза.
# Это заведомо плохая упаковка: её и предстоит привести в порядок через агента.

# python:3.12.16-slim-trixie, manifest-list digest.
# slim: без компиляторов и dev-пакетов в базе; trixie: 0 CRITICAL в trivy на момент работы.
FROM python:3.12.16-slim-trixie@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b

ENV ADMIN_TOKEN=launch-control-dev-token
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    vim \
    curl \
    net-tools \
    procps

RUN pip install --upgrade pip
RUN pip install uv

WORKDIR /app

COPY . .

RUN uv pip install --system -r pyproject.toml --extra dev

RUN pytest -q

EXPOSE 8000

CMD uvicorn app.main:app --host 0.0.0.0 --port 8000
