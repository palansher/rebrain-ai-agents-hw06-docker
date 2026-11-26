
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
