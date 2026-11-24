# docker-lab — вариант B задания «AI-агенты в DevOps»

Сервис **Launch Control** (FastAPI, Python 3.12, uv) с заведомо плохой упаковкой. Сервис работает и покрыт
тестами - проблема не в коде, а в том, как он собран в образ: образ весит больше гигабайта и пересобирается
минуты после правки одной строки.

Приложение (`app/`, `tests/`) менять нельзя. Задача - привести в порядок `Dockerfile`, не сломав поведение,
работая через coding-агента, и довести табло `scripts/score.sh` до **9/9**. Список дефектов нигде не дан -
ищите инструментами (`hadolint`, `dive`, `trivy`, замер пересборки).

```bash
./scripts/tools.sh            # проверить окружение
uv lock                       # если нет lock-файла
./scripts/bench.sh baseline   # 4 метрики -> bench-results.md
BASELINE_MB=<размер> ./scripts/score.sh baseline
uv run --extra dev pytest     # 17 тестов должны проходить
```

Smoke (эндпоинты, которые нельзя сломать): `GET /health`->200; `GET /api/v1/launches`->200, 5 миссий;
`POST /api/v1/launches/LC-101/countdown`->200, `t_minus_seconds=600`; `POST /api/v1/launches/LC-102/countdown`->409.
