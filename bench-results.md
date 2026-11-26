
## baseline

| Метрика | Значение |
| --- | --- |
| Размер образа | 1412 MB |
| Холодная сборка | 100 s |
| **Тёплая пересборка** | **6 s** |
| Слоёв в истории | 24 |

Самые тяжёлые шаги:

```
7.71MB     RUN /bin/sh -c pytest -q # buildkit
149MB      RUN /bin/sh -c uv pip install --system -r pyproject.toml --extra dev #
318kB      COPY . . # buildkit
58.1MB     RUN /bin/sh -c pip install uv # buildkit
17.8MB     RUN /bin/sh -c pip install --upgrade pip # buildkit
```

## step1-dockerignore

| Метрика | Значение |
| --- | --- |
| Размер образа | 1412 MB |
| Холодная сборка | 31 s |
| **Тёплая пересборка** | **6 s** |
| Слоёв в истории | 24 |

Самые тяжёлые шаги:

```
7.71MB     RUN /bin/sh -c pytest -q # buildkit
149MB      RUN /bin/sh -c uv pip install --system -r pyproject.toml --extra dev #
236kB      COPY . . # buildkit
58.1MB     RUN /bin/sh -c pip install uv # buildkit
17.8MB     RUN /bin/sh -c pip install --upgrade pip # buildkit
```

## step2-slim

| Метрика | Значение |
| --- | --- |
| Размер образа | 811 MB |
| Холодная сборка | 61 s |
| **Тёплая пересборка** | **12 s** |
| Слоёв в истории | 21 |

Самые тяжёлые шаги:

```
7.71MB     RUN /bin/sh -c pytest -q # buildkit
149MB      RUN /bin/sh -c uv pip install --system -r pyproject.toml --extra dev #
237kB      COPY . . # buildkit
58.1MB     RUN /bin/sh -c pip install uv # buildkit
17.8MB     RUN /bin/sh -c pip install --upgrade pip # buildkit
```

## step3-multistage

| Метрика | Значение |
| --- | --- |
| Размер образа | 311 MB |
| Холодная сборка | 10 s |
| **Тёплая пересборка** | **0 s** |
| Слоёв в истории | 16 |

Самые тяжёлые шаги:

```
7.7kB      COPY app ./app # buildkit
192MB      COPY /app/.venv /app/.venv # buildkit
36B        RUN /bin/sh -c set -eux;  for src in idle3 pip3 pydoc3 python3 python3
36.8MB     RUN /bin/sh -c set -eux;   savedAptMark="$(apt-mark showmanual)";  apt
3.81MB     RUN /bin/sh -c set -eux;  apt-get update;  apt-get install -y --no-ins
```

## step4-final

| Метрика | Значение |
| --- | --- |
| Размер образа | 160 MB |
| Холодная сборка | 2 s |
| **Тёплая пересборка** | **1 s** |
| Слоёв в истории | 16 |

Самые тяжёлые шаги:

```
7.7kB      COPY app ./app # buildkit
40.7MB     COPY /app/.venv /app/.venv # buildkit
36B        RUN /bin/sh -c set -eux;  for src in idle3 pip3 pydoc3 python3 python3
36.8MB     RUN /bin/sh -c set -eux;   savedAptMark="$(apt-mark showmanual)";  apt
3.81MB     RUN /bin/sh -c set -eux;  apt-get update;  apt-get install -y --no-ins
```

## optimized

| Метрика | Значение |
| --- | --- |
| Размер образа | 160 MB |
| Холодная сборка | 2 s |
| **Тёплая пересборка** | **1 s** |
| Слоёв в истории | 19 |

Самые тяжёлые шаги:

```
4.31kB     RUN /bin/sh -c useradd --system --uid 10001 --no-create-home appuser #
7.7kB      COPY app ./app # buildkit
40.7MB     COPY /app/.venv /app/.venv # buildkit
36B        RUN /bin/sh -c set -eux;  for src in idle3 pip3 pydoc3 python3 python3
36.8MB     RUN /bin/sh -c set -eux;   savedAptMark="$(apt-mark showmanual)";  apt
```
