# Launch Control — вариант B: оптимизация Docker-образа

Учебное задание «AI-агенты в DevOps». Сервис **Launch Control** (FastAPI, Python 3.12, uv) упакован в образ,
который весит больше гигабайта и пересобирается после правки одной строки. Задача — привести упаковку в порядок
**через coding-агента**, не меняя поведение приложения, и доказать результат измерениями.

- Публичный репозиторий: <https://github.com/palansher/rebrain-ai-agents-hw06-docker>
- Агент: OpenCode 2.4.2, модель `opencode-go/deepseek-v4.1-flash`
- Приложение (`app/`, `tests/`) не менялось: `git diff baseline..optimized -- app tests` пуст

## Коротко: до и после

| Метрика | До (`baseline`) | После (`optimized`) |
|---|---|---|
| Размер образа | **1412 MB** | **160 MB** (×8.8) |
| Слоёв в истории | 24 | 19 |
| Холодная сборка (`--no-cache`) | 100 s | 2 s |
| Тёплая пересборка после правки `app/main.py` | 6 s, зависимости переустанавливаются | 1 s, слой `uv sync` — `CACHED` |
| `scripts/score.sh` | **0/9** | **9/9** |
| `hadolint` | 0 error / 7 warning | 0 error / 0 warning |
| `dive` efficiency / wasted | 98.84 % / 23.2 MB | 97.55 % / 5.65 MB |
| `trivy` debian | 2924 (HIGH 194, CRITICAL 3) | 225 (HIGH 54, CRITICAL 0) |
| `trivy` python-pkg | 3 (HIGH 1) | 7 (HIGH 0) |
| Контекст сборки | 324.6 kB (+145 MB `.venv` без `.dockerignore`) | 220.4 kB |
| Тесты | 18 passed | 18 passed |

> Про `dive`: efficiency у baseline **выше**, чем у оптимизированного образа. Это не регресс, а свойство метрики —
> dive считает «мусор внутри слоёв» (перезаписанные/удалённые файлы), а не нужность слоя. Абсолютный wasted space
> упал с 23.2 MB до 5.65 MB. Подробно — в разделе 5.

---

## 1. Что сдаётся

```text
Dockerfile              # multi-stage, pinned digest, non-root, HEALTHCHECK
.dockerignore
.gitignore
pyproject.toml          # pandas/numpy -> extra "analytics"
uv.lock
app/ tests/ tools/      # без изменений
scripts/
├── smoke.sh            # новый: проверяет поведение, падает при ошибке
├── bench.sh            # без изменений
├── score.sh            # без изменений
└── tools.sh            # без изменений
bench-results.md        # все замеры: baseline, step1..step4, optimized
evidence/               # сырые выводы инструментов и журнал работы с агентом
AGENTS.md               # ограничения для агента
README.md               # этот файл
```

### Как запускать

```bash
./scripts/tools.sh                     # проверка окружения
./scripts/bench.sh baseline            # 4 метрики -> bench-results.md
./scripts/score.sh baseline            # табло (0/9 на исходном Dockerfile)
docker build -t launch-control:optimized .
./scripts/score.sh optimized           # 9/9
./scripts/smoke.sh launch-control:optimized
uv run --frozen --extra dev pytest -q  # 18 тестов
uv run --frozen --extra analytics python -m tools.analyze_launches
```

### Версии (без них цифры невоспроизводимы)

| Инструмент | Версия |
|---|---|
| Docker (BuildKit) | 29.10.0 |
| uv | 0.13.8 |
| hadolint | 2.15.1 |
| dive | 0.13.1 |
| trivy | 0.76.2, БД/bundle от 2026-11-26 |
| jq | 1.7 |
| Базовый образ | `python:3.12.16-slim-trixie@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b` |
| Python в образе | 3.12.16, Debian 13.8 (trixie) |
| OpenCode / модель | 2.4.2 / `opencode-go/deepseek-v4.1-flash` |

Целевая версия Kubernetes не применима: вариант B работает только с локальным Docker-демоном.

---

## 2. Что было не так: baseline

Снято **до** любых правок, `./scripts/bench.sh baseline` и `./scripts/score.sh baseline`.

```text
## baseline
| Размер образа        | 1412 MB |
| Холодная сборка      | 100 s   |
| Тёплая пересборка    | 6 s     |
| Слоёв в истории      | 24      |
контекст сборки: 324.60 kB
```

Табло — **0/9**:

```text
✗ Размер <= 400 MB — 1412 MB
✗ Работает не от root — root
✗ Есть HEALTHCHECK
✗ Нет компилятора в runtime — найдено: gcc cc g++ make
✗ Нет dev-инструментов — найдено: git vim wget curl pytest uv
✗ Тесты и мусор не едут в образ — внутри: /app/tests /app/.git /app/pyproject.toml
✗ Нет секретов в ENV и в истории — ADMIN_TOKEN в Config.Env
✗ .dockerignore есть — файла нет
✗ hadolint чист (>= warning) — 0 error, 7 warning
```

`hadolint` (полный вывод — `evidence/baseline/hadolint.txt`): DL3064 (секрет в ENV), DL3008 (apt без версий),
DL3013/DL3042 (pip без версий и с кешем), DL3025 (CMD в shell-форме).

`dive`: efficiency 98.84 %, wasted 23.2 MB.
`trivy`: debian 2924 уязвимостей (HIGH 194, CRITICAL 3), python-pkg 3 (HIGH 1).
Тесты: **18 passed** (в тексте задания написано 17 — см. раздел 8).

Дефекты упаковки: полная база `python:3.12`; `build-essential` и dev-пакеты в runtime; незапиненные `pip`/`uv`;
`COPY . .` до установки зависимостей; `--extra dev` в образе; `RUN pytest` и тесты внутри; `ENV ADMIN_TOKEN`;
нет `.dockerignore`; root; нет `HEALTHCHECK`; `CMD` в shell-форме; база не зафиксирована.

---

## 3. Как работали с агентом

Цикл: `промпт → правка агентом → независимая проверка инструментом → решение`.
Промпты и критерии приёмки — в `steps-docker.md` (вне репозитория), журнал решений — `evidence/agent-log.md`.

**Промпт P0 (baseline, без правок):**

```text
Сегодня шаг baseline: ничего не оптимизируем, только фиксируем «до».
Ничего не меняй в Dockerfile, app/ и tests/. Не коммить.
Сними bench/score/hadolint/dive/trivy/history/context, после baseline — локальные тесты.
Покажи фактический вывод и таблицу.
```

**Промпт P1 (аудит):**

```text
Перечисли все дефекты упаковки. Для каждого: файл:строка, суть и каким инструментом он ловится
(пункт score.sh, правило hadolint, dive, trivy, либо только замер тёплой пересборки).
Сверь pyproject.toml с реальными импортами app/ tools/ tests/.
Проверь, используется ли ADMIN_TOKEN в коде.
Предложи приёмы и отдельно — что отверг и почему. Никаких правок.
```

**Промпт P7 (hardening):**

```text
Доведи до 9/9: non-root (uid 10001), HEALTHCHECK только на stdlib Python (curl/wget в slim нет),
убрать ADMIN_TOKEN, CMD в JSON-форме, база с digest. hadolint — 0 error / 0 warning.
Покажи фактический вывод: score, smoke, inspect, history.
```

Ключевые ответы агента и решения:

| Что предложил агент | Решение |
|---|---|
| `python:3.12-slim-trixie` + digest, `uv sync` в builder, копирование `.venv` | принято, подтверждено сборкой и 9/9 |
| `USER 10001:10001` + `HEALTHCHECK` на `urllib` | принято, `docker run ... id` → uid 10001, health `healthy` |
| `pandas`/`numpy` вынести в extra `analytics`, не удалять | принято: `app/` их не импортирует, но `tools/analyze_launches.py` импортирует |
| alpine «ради 49 МБ» | **отклонено**, см. 4.1 |
| distroless | **отклонено**, см. 4.2 |
| измерить варианты через `bench.sh tag -f Dockerfile.stepN` | **отклонено**, см. 4.3 |
| поставить `curl` для healthcheck | **отклонено**, см. 4.5 |

---

## 4. Что агент предложил, а мы отклонили

### 4.1. Alpine как база (меньше на 70 МБ) — отклонено

Проверка:

```text
$ docker run --rm python:3.12-alpine3.22 sh -c 'command -v wget'
/usr/bin/wget          # busybox applet
```

`score.sh` пункт 5 ищет `wget` среди dev-инструментов и **валит проверку**. Плюс musl и риск отсутствия
wheel'ов для `uvloop`/`httptools`. Взяли `slim-trixie`: 119 МБ базы вместо 49 МБ, зато 9/9 достижимо без хаков.

### 4.2. Distroless — отклонено

В `score.sh` проверки 4–6 устроены так: если в образе нет `sh`, они **автоматически зелёные** с формулировкой
«шелла нет — проверять нечем». То есть distroless даёт зелёное табло **без реальной проверки** — ровно тот
антипаттерн, о котором предупреждает задание («зелёный результат может означать „не проверял“»).
Плюс `HEALTHCHECK` и entrypoint становятся хрупкими. Оставили проверяемый slim.

### 4.3. Замер промежуточных вариантов через `bench.sh tag -f Dockerfile.stepN` — отклонено

В тексте задания так написано, но скрипт принимает **только тег**:

```text
TAG="${1:-baseline}"                     # bench.sh
docker build --no-cache -t "$IMAGE" .    # -f нигде не передаётся
```

Второй аргумент игнорируется → под тегом `step1-slim` собрался бы **текущий** Dockerfile, и таблица
вкладов была бы ложной. Меряли иначе: последовательные коммиты + git-теги, по одному изменению на шаг.

### 4.4. `uv run` с локальным индексом — отклонено (поймано на ревью diff)

На машине стоит `/etc/uv/uv.toml` с внутренним Nexus, и первый `uv run` переписал `uv.lock`
на `http://vs-nexus02.brg.loc:8081/...`. В публичный репозиторий утёк бы внутренний хост, а у преподавателя
lock не разрешился бы. Откатили, дальше: `uv run --frozen`, relock — `uv lock --default-index https://pypi.org/simple`,
проверка `grep -n 'vs-nexus' uv.lock` → пусто.

### 4.5. `apt-get install curl` для HEALTHCHECK — отклонено

Плюс ~10 МБ, `hadolint` DL3008 (warning) и красный пункт 5 табло (`curl` в runtime). Сделали healthcheck
на stdlib: `python -c "urllib.request.urlopen(...)"` — без новых пакетов.

---

## 5. Цифры, вклад приёмов и оговорки

### 5.1. Пошаговые замеры (`bench-results.md`)

| Приём | Тег | Размер | Δ | Слоёв | Cold | Warm | score |
|---|---|---|---|---|---|---|---|
| baseline | `baseline` | 1412 MB | — | 24 | 100 s | 6 s | 0/9 |
| + `.dockerignore` | `step1-dockerignore` | 1412 MB | 0 | 24 | 31 s | 6 s | 1/9 |
| + slim-база | `step2-slim` | 811 MB | −601 MB | 21 | 61 s | 12 s | 1/9 |
| + multi-stage | `step3-multistage` | 311 MB | −500 MB | 16 | 10 s | 0 s | 6/9 |
| + без dev/analytics | `step4-final` | 160 MB | −151 MB | 16 | 2 s | 1 s | 7/9 |
| + non-root/healthcheck | `optimized` | 160 MB | 0 | 19 | 2 s | 1 s | **9/9** |

Оговорки, без которых таблица врёт:

- **Размер** — детерминированная метрика, ей можно верить.
- **Cold/warm** шумят: step1 «ускорился» со 100 до 31 s при том же Dockerfile — это разница кэшей/сети,
  а не улучшение. Поэтому вывод про кэш слоёв делаем не по секундам, а по build-логу: у `optimized`
  шаг `uv sync --frozen` — `CACHED` (`evidence/after/warm-build.txt`), у baseline `uv pip install` выполняется заново.
- **Тезис «пересобирается минуты» не воспроизвёлся**: baseline warm = 6 s (uv + быстрый канал). Честный
  результат: 6 s → 1 s и, главное, зависимости больше не переустанавливаются.
- **`.dockerignore` не уменьшает образ** (Δ=0): он уменьшает контекст (324.6 kB → 220.4 kB) и не даёт
  отправить в контекст `.venv` (145 MB) и `.git`. Это страховка, а не оптимизация размера.

### 5.2. Почему `dive` показывает efficiency ниже

`dive` считает «wasted» файлы, которые были перезаписаны/удалены внутри слоёв, а не файлы, которые «не нужны».
У baseline 1.4 ГБ почти целиком «полезны» по этой модели (98.84 %), у оптимизированного образа 5.65 MB
перезаписей (97.55 %). Сравнивать efficiency между образами разного размера бессмысленно; корректные выводы:

| | baseline | optimized |
|---|---|---|
| wasted bytes | 23.2 MB | **5.65 MB** |
| размер | 1412 MB | **160 MB** |

---

## 6. Чем пойман каждый дефект (какой слой проверки)

| # | Дефект | Слой, который поймал | Доказательство исправления |
|---|---|---|---|
| 1 | Полная база 1.4 ГБ | `bench.sh` (размер), `dive` | 160 MB, `evidence/*/bench.txt` |
| 2 | `build-essential`, `git`, `vim`, `curl` | `score.sh` п.4–5, `dive` | пункты зелёные, `command -v` пуст |
| 3 | Незапиненные `pip`/`uv`, pip-кеш | `hadolint` DL3013/DL3042 | 0 warning |
| 4 | `COPY . .` до зависимостей | **только замер** + build-лог | warm 1 s, `uv sync` CACHED |
| 5 | `--extra dev` в runtime | `score.sh` п.5 (`pytest`) | пункт зелёный |
| 6 | Тесты и `.git` в образе | `score.sh` п.6 | `/app/tests` нет |
| 7 | `ADMIN_TOKEN` в ENV/history | `hadolint` DL3064 + `score.sh` п.7 + `docker history` | 0 вхождений |
| 8 | Нет `.dockerignore` | `score.sh` п.8 + размер контекста | 11 правил, 220.4 kB |
| 9 | root | `score.sh` п.2 | `User=10001:10001` |
| 10 | Нет `HEALTHCHECK` | `score.sh` п.3 | `Health=yes`, статус `healthy` |
| 11 | `CMD` shell-форма | `hadolint` DL3025 | JSON-форма |
| 12 | База не зафиксирована | **ревью** (табло не проверяет) | тег + digest |
| 13 | `pandas`/`numpy` в runtime | **сверка импортов** + размер | extra `analytics`, 160 MB |
| 14 | apt-листы, pip-кеш | `dive` + `hadolint` info | multi-stage, без pip/apt в runtime |
| 15 | Нет проверки поведения | **наш `smoke.sh`** | `evidence/smoke/*` |

Вывод: **ни один инструмент не заменяет остальные.** hadolint видит текст Dockerfile, но не видит размер и
поведение; score видит состав образа, но не видит кэш слоёв и не проверяет сервис; trivy видит CVE, но не
видит, что сервис не стартует; smoke видит поведение, но не видит упаковку.

---

## 7. Что осталось незакрытым и почему

1. **54 HIGH в Debian-пакетах базового образа** (`libssl3t64`, `util-linux`, `perl-base` и др.).
   Почти все — `affected` (фикса в trixie ещё нет), один `fixed` (`libzstd1`), один `fix_deferred`.
   Разовая правка не решает: нужен процесс обновления базового образа (пересборка при выходе digest'а,
   Renovate/Dependabot + пересборка раз в неделю). Ставить `apt-get upgrade` в Dockerfile не стали:
   это делает сборку невоспроизводимой и добавляет слой.
2. **`pip` остаётся в базовом образе** и даёт часть python-CVE. В рантайме он не нужен; можно удалить
   (`rm -rf .../pip*`), но это хак против базового образа, а не архитектурное решение — вынесено в техдолг.
3. **Нет multi-arch сборки** (проверено только amd64) и **SBOM/подписи** (`trivy --format cyclonedx`,
   cosign) — за рамками задания.
4. **Digest обновляется вручную** — нет автоматики.
5. **Тесты не запускаются внутри сборки**: `.dockerignore` отсекает `tests/`, чтобы они не ехали в образ.
   Их место — CI-job рядом со сборкой; локально `pytest` и `smoke.sh` это закрывают.
6. **Тёплая пересборка измерена на этой машине** (быстрый канал, локальный кэш колёс); на чистом CI
   цифры cold будут другими — важна не абсолютная секунда, а факт, что слой зависимостей кэшируется.

---

## 8. Замечания к стенду: где задание и скрипты не согласуются (и как мы это обошли)

Раздел для преподавателя: это реальные расхождения, найденные при выполнении. Мы их не «подгоняли»,
а обходили и фиксировали.

| # | Что написано | Что на самом деле | Как обошли |
|---|---|---|---|
| 1 | «17 тестов» | **18** (`tests/test_api.py` 12 + `test_catalog.py` 6), `pytest -q` → 18 passed | фиксируем 18; это не ошибка выполнения |
| 2 | `./scripts/bench.sh step1-slim -f Dockerfile.step1` | `bench.sh` читает только `$1` (тег), `-f` игнорируется, собирается текущий `Dockerfile` → **ложный замер** | меряем через коммиты и git-теги, по одному приёму на шаг |
| 3 | `BASELINE_MB=<размер> ./scripts/score.sh baseline` | переменная `BASELINE_MB` в `score.sh` не используется; лимит — `SIZE_LIMIT_MB` (400) | вызываем `score.sh` без `BASELINE_MB` |
| 4 | «hadolint без ошибок — 4 error» (пример табло) | на baseline **0 error, 7 warning, 5 info**; табло валит пункт 9 именно по warning | исправляем warning'и, правила не подавляем |
| 5 | `scripts/.gitignore` «игнорирует `bench-results.md`» | паттерн лежит в `scripts/`, действует только на `scripts/bench-results.md`; корневой файл **не игнорируется** (`git check-ignore` → exit 1) | ничего не правили: корневой `bench-results.md` должен быть в git как доказательство |
| 6 | «`python tools/analyze_launches.py` работает» | без `PYTHONPATH=.` падает `ModuleNotFoundError: app` (и до наших правок) | проверяем `uv run --frozen --extra analytics python -m tools.analyze_launches` |
| 7 | `.dockerignore` должен отсекать `tests/` | если исключить `tests/` до удаления `RUN pytest`, baseline-сборка падает (pytest exit 5) | добавляем `tests/` в `.dockerignore` только на шаге multi-stage, когда `RUN pytest` убран |
| 8 | `score.sh`: «шелла нет — проверять нечем» | distroless получает зелёные пункты 4–6 **без проверки** | distroless не используем; ограничение описано в 4.2 |
| 9 | `score.sh` п.7 «Нет секретов» | ищет только строку `ADMIN_TOKEN`, другие секреты не увидит | дополнительно `git grep` по репозиторию и `docker history` |
| 10 | Ориентир «≤ ¼ baseline» (~356 MB) | в `score.sh` порог фиксированный — 400 MB | ориентируемся на более строгий (¼); 160 MB проходит оба |
| 11 | «пересобирается несколько минут после правки строки» | baseline warm = **6 s**, cold = 100 s (uv + быстрый канал) | показываем и время, и факт переустановки зависимостей |
| 12 | «dive показывает заметно более высокий efficiency» | baseline **98.84 %** > optimized **97.55 %** | сравниваем размер и absolute wasted bytes; объясняем метрику (5.2) |
| 13 | `bench.sh` «слоёв в истории» | считает и служебные слои (`docker history -q \| wc -l`), метрика условная | используем как относительную |
| 14 | локальный `uv` | системный `/etc/uv/uv.toml` подменяет индекс на внутренний Nexus, `uv run` переписывает `uv.lock` | `uv run --frozen`; `uv lock --default-index https://pypi.org/simple`; проверка `grep -n 'vs-nexus' uv.lock` |
| 15 | baseline-коммит содержит `ENV ADMIN_TOKEN=launch-control-dev-token` | это учебный фейковый токен из стенда, не реальный секрет, но он остаётся в истории git | историю не переписываем (иначе ломаются baseline-доказательства), явно помечаем здесь |

---

## 9. Воспроизведение по шагам

```bash
git checkout baseline && ./scripts/bench.sh baseline        # 1412 MB, 24 слоя, 0/9
git checkout step1-dockerignore  && ./scripts/bench.sh step1-dockerignore
git checkout step2-slim          && ./scripts/bench.sh step2-slim
git checkout step3-multistage    && ./scripts/bench.sh step3-multistage
git checkout step4-final         && ./scripts/bench.sh step4-final
git checkout optimized           && ./scripts/bench.sh optimized && ./scripts/score.sh optimized
```

Теги: `baseline`, `step1-dockerignore`, `step2-slim`, `step3-multistage`, `smoke`, `step4-final`, `optimized`.
Сырые выводы: `evidence/baseline/`, `evidence/step1..4/`, `evidence/after/`, `evidence/smoke/`,
журнал работы с агентом — `evidence/agent-log.md`.
