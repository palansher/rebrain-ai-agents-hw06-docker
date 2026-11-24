#!/usr/bin/env bash
# Проверка окружения перед демо. Запускать до эфира, не на эфире.
set -uo pipefail

ok=0
missing=0

check() {
  local name="$1" hint="$2" required="$3"
  if command -v "$name" >/dev/null 2>&1; then
    printf '  \033[32m✓\033[0m %-12s %s\n' "$name" "$("$name" --version 2>&1 | head -n1)"
    ok=$((ok + 1))
  elif [ "$required" = "required" ]; then
    printf '  \033[31m✗\033[0m %-12s НЕТ — %s\n' "$name" "$hint"
    missing=$((missing + 1))
  else
    printf '  \033[33m•\033[0m %-12s нет (необязательно) — %s\n' "$name" "$hint"
  fi
}

echo
echo "Инструменты стенда"
echo
check docker   "https://docs.docker.com/get-docker/"            required
check uv       "curl -LsSf https://astral.sh/uv/install.sh | sh" required
check hadolint "brew install hadolint"                          required
check dive     "brew install dive"                              optional
check trivy    "brew install trivy"                             optional
check jq       "brew install jq"                                optional

echo
if ! docker info >/dev/null 2>&1; then
  printf '  \033[31m✗\033[0m демон Docker не отвечает — запустите Docker Desktop\n'
  missing=$((missing + 1))
else
  printf '  \033[32m✓\033[0m демон Docker отвечает\n'
fi

echo
if [ "$missing" -gt 0 ]; then
  echo "Не хватает обязательных инструментов: $missing. Демо не поедет."
  exit 1
fi

echo "Окружение готово."
echo "Дальше: uv lock && ./scripts/bench.sh baseline"
echo
