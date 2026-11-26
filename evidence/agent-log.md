# evidence/agent-log.md — журнал «промпт → ответ → решение»

Здесь фиксируются реальные промпты, ключевые ответы агента и решения человека.
Это сырьё для раздела README «Как работали с агентом» и «Что агент предложил, а я отклонил».

Формат записи:

```
## <шаг/промпт> — <дата время>

PROMPT:
<текст промпта>

AGENT (ключевое):
<2-5 строк ответа>

DECISION:
принято / отклонено (почему), чем подтверждено
```

---

## Шаг 0. Setup — 2026-11-27

PROMPT:
Подготовить репозиторий к работе: `.gitignore` (venv, кэши), перестать игнорировать `bench-results.md`,
создать `evidence/agent-log.md`, закоммитить.

AGENT:
Выполнено.

DECISION:
принято.

---

## Шаг 1. Baseline — 2026-11-27

PROMPT (P0):
«Ничего не меняй. Сними baseline: bench, score, hadolint, dive, trivy, history, context;
после baseline — локальные тесты. Покажи фактический вывод и таблицу».

AGENT (ключевое):
- размер 1412 MB, 24 слоя, cold 100 s, warm 6 s, контекст 324.60 kB;
- score 0/9; hadolint 0 error / 7 warning / 5 info; trivy debian 2924 (HIGH 194, CRITICAL 3);
- тесты 18 passed (в задании 17).

DECISION:
принято. Зафиксировано расхождение: «тёплая пересборка — минуты» на этой машине не воспроизводится
(6 s), поэтому дальше меряем и время, и факт переустановки зависимостей.
Обнаружено: системный `/etc/uv/uv.toml` подменяет индекс на внутренний Nexus и `uv run` переписал
`uv.lock`. Откатили lock, дальше используем `uv run --frozen`, relock — с `--default-index https://pypi.org/simple`.

---

## Шаг 2. Аудит (без правок) — 2026-11-27

PROMPT (P1):
«Перечисли дефекты и слой проверки для каждого; сверь pyproject с импортами; проверь ADMIN_TOKEN;
предложи приёмы и отдельно — что отверг и почему».

AGENT (ключевое):
1. Дефекты: полная база python:3.12; apt build-essential/git/vim/curl; незапиненные pip/uv;
   `COPY . .` до установки зависимостей; `--extra dev` в runtime; `RUN pytest` и tests в образе;
   `ENV ADMIN_TOKEN`; нет `.dockerignore`; root; нет HEALTHCHECK; CMD в shell-форме; база не запинена.
2. Зависимости: app/ использует только fastapi/pydantic/stdlib; pandas+numpy нужны только
   tools/analyze_launches.py; pytest/httpx — только тестам.
3. ADMIN_TOKEN в коде не используется (grep пуст) → можно удалять.
4. Приёмы по эффекту: slim-база → multi-stage → чистка зависимостей → порядок слоёв → non-root/healthcheck.
5. Отвергнуто агентом (и проверено):
   - alpine: busybox `wget` (/usr/bin/wget) валит п.5 score.sh; musl-риски;
   - distroless: нет sh → п.4–6 «зелёные без проверки», HEALTHCHECK/entrypoint хрупкие;
   - `apt-get install curl` для HEALTHCHECK: п.5 + DL3008; healthcheck на stdlib Python;
   - удалить pandas/numpy совсем: сломает tools/analyze_launches.py (нужен extra analytics);
   - мерить варианты через `bench.sh tag -f ...`: флаг игнорируется, замер врёт.

DECISION:
принято; базой выбрана python:3.12.16-slim-trixie (0 CRITICAL, glibc), см. analysis-task-docker.md §9.

---

## Шаг 3. `.dockerignore` — 2026-11-27

PROMPT (P2):
«Исключи .git/.venv/кэши/тесты/tools/evidence; tests/ пока оставь (baseline делает RUN pytest);
измерь контекст; затем ./scripts/bench.sh step1-dockerignore; покажи diff, не коммить».

AGENT (ключевое):
контекст 324.60 kB → 220.39 kB; `.venv` 144.6 MB исключён; образ не изменился (1412 MB), score 1/9.
Первый прогон `bench.sh` показал «transferring context: 1.14 kB» — это дельта кэша BuildKit,
а не реальный контекст; для честного числа использовали первый билд после изменения `.dockerignore`.

DECISION:
принято. Зафиксировали: `.dockerignore` не уменьшает образ, он уменьшает контекст и страхует от утечек.

---

## Шаг 4. Slim-база — 2026-11-27

PROMPT (P3):
«Замени базу на python:3.12.16-slim-trixie@sha256:1910…, остальную логику одноступенчатой сборки сохрани;
USER/HEALTHCHECK/секрет не трогай; hadolint будет ругаться — не подавляй».

AGENT (ключевое):
1412 → 811 MB, 21 слой, cold 61 s, warm 12 s, score 1/9.

DECISION:
принято. Warm вырос из-за переустановки apt/pip на slim — это ожидаемо и будет убрано multi-stage.

---

## Шаг 5. Multi-stage — 2026-11-27

PROMPT (P4):
«builder ставит зависимости по uv.lock, runtime — только venv и app; убери RUN pytest и добавь tests/ в
.dockerignore; зависимости до COPY app; extra dev сохрани; USER/HEALTHCHECK не добавляй».

AGENT (ключевое):
311 MB, 16 слоёв, cold 10 s, warm 0 s, score 6/9 (зелёные 1,4,5,6,7,8,9; красные root и HEALTHCHECK).
Зависимости действительно ставятся до исходников: в warm-логе `uv sync` — CACHED, меняется только COPY app.

DECISION:
принято. Заодно ушли `ADMIN_TOKEN` и shell-CMD — поэтому score вырос сразу до 6/9, а не до 4/9.

---

## Шаг 6. Smoke — 2026-11-27

PROMPT (P5):
«Создай scripts/smoke.sh: 4 эндпоинта, 5 миссий, коды 200/409, ожидание готовности, trap, exit 1 при ошибке;
негативный тест — образ с портом 8001, smoke должен упасть».

AGENT (ключевое):
positive: все проверки ✓, exit 0; negative: сервис слушает 8001, `/health` на 8000 недоступен → exit 1.

DECISION:
принято. Скрипт не «мягкий»: падает и по коду, и по телу ответа (5 миссий, 600 секунд, status=counting).

---

## Шаг 7. Зависимости — 2026-11-27

PROMPT (P6):
«pandas/numpy — в extra analytics (не удалять), uv lock, из Dockerfile убрать extra dev; покажи Δ и проверки».

AGENT (ключевое):
`uv lock` попытался записать внутренний Nexus (см. шаг 1) — выполнено с `--default-index https://pypi.org/simple`;
lock чистый (`vs-nexus` = 0). 311 → 160 MB, warm 1 s, score 7/9. Тесты 18 passed, analytics-скрипт работает.

DECISION:
принято; Δ −151 MB — это в основном pandas+numpy (≈100 MB) плюс dev-пакеты.

---

## Шаг 8. Hardening — 2026-11-27

PROMPT (P7):
«non-root uid 10001, HEALTHCHECK на stdlib, ADMIN_TOKEN убрать, CMD JSON, база с digest, hadolint 0/0».

AGENT (ключевое):
score 9/9; hadolint exit 0; `User=10001:10001`, `Health=yes`, статус `healthy`, uid 10001; `ADMIN_TOKEN` — 0.

DECISION:
принято. 9/9 достигнуто без ослабления проверок (score/bench/hadolint не менялись).
