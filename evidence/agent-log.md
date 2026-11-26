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
