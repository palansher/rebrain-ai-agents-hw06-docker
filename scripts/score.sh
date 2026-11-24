#!/usr/bin/env bash
# Табло из 9 проверок. Критерий готовности для агента — 9/9.
#
#   ./scripts/score.sh baseline
#   ./scripts/score.sh after-agent
#
# Проверки специально разнородные: часть смотрит на метаданные образа,
# часть заглядывает внутрь, часть — на репозиторий. Ни один инструмент
# из тех, что запускают отдельно, не покрывает весь список.
set -uo pipefail

TAG="${1:-baseline}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IMAGE="launch-control:${TAG}"
SIZE_LIMIT_MB="${SIZE_LIMIT_MB:-400}"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Нет образа $IMAGE. Сначала: ./scripts/bench.sh ${TAG}"
  exit 1
fi

passed=0
total=0

# printf %-34s считает байты, а метки кириллические — выравниваем по символам.
label() {
  local text="$1" width=36 chars pad
  chars=$(printf '%s' "$text" | wc -m | tr -d ' ')
  pad=$(( width - chars ))
  [ "$pad" -lt 1 ] && pad=1
  printf '%s%*s' "$text" "$pad" ''
}

pass() { printf '  \033[32m✓\033[0m %s %s\n' "$(label "$1")" "${2:-}"; passed=$((passed + 1)); }
fail() { printf '  \033[31m✗\033[0m %s %s\n' "$(label "$1")" "${2:-}"; }
count() { total=$((total + 1)); }

# Запустить команду внутри образа. Если шелла нет вообще (distroless),
# возвращаем especial-код 127 — вызывающий считает это успехом проверки.
in_image() {
  docker run --rm --entrypoint sh "$IMAGE" -c "$1" 2>/dev/null
}
has_shell() {
  docker run --rm --entrypoint sh "$IMAGE" -c 'exit 0' >/dev/null 2>&1
}

echo
echo "=== score: $IMAGE ==="
echo

SHELL_AVAILABLE=no
has_shell && SHELL_AVAILABLE=yes

# 1 -------------------------------------------------------------- размер
count
size_mb=$(( $(docker image inspect -f '{{.Size}}' "$IMAGE") / 1000 / 1000 ))
if [ "$size_mb" -le "$SIZE_LIMIT_MB" ]; then
  pass "Размер <= ${SIZE_LIMIT_MB} MB" "${size_mb} MB"
else
  fail "Размер <= ${SIZE_LIMIT_MB} MB" "${size_mb} MB"
fi

# 2 ---------------------------------------------------------------- root
count
user=$(docker image inspect -f '{{.Config.User}}' "$IMAGE")
if [ -n "$user" ] && [ "$user" != "root" ] && [ "$user" != "0" ]; then
  pass "Работает не от root" "$user"
else
  fail "Работает не от root" "${user:-root}"
fi

# 3 --------------------------------------------------------- HEALTHCHECK
count
if [ -n "$(docker image inspect -f '{{if .Config.Healthcheck}}yes{{end}}' "$IMAGE")" ]; then
  pass "Есть HEALTHCHECK"
else
  fail "Есть HEALTHCHECK"
fi

# 4 ----------------------------------------------------------- компилятор
count
if [ "$SHELL_AVAILABLE" = "no" ]; then
  pass "Нет компилятора в runtime" "шелла нет — проверять нечем"
else
  found=$(in_image 'for b in gcc cc g++ make; do command -v $b >/dev/null 2>&1 && echo $b; done' | tr '\n' ' ')
  if [ -z "$found" ]; then
    pass "Нет компилятора в runtime"
  else
    fail "Нет компилятора в runtime" "найдено: $found"
  fi
fi

# 5 --------------------------------------------------------- dev-инструменты
count
if [ "$SHELL_AVAILABLE" = "no" ]; then
  pass "Нет dev-инструментов" "шелла нет — проверять нечем"
else
  found=$(in_image 'for b in git vim wget curl pytest uv; do command -v $b >/dev/null 2>&1 && echo $b; done' | tr '\n' ' ')
  if [ -z "$found" ]; then
    pass "Нет dev-инструментов"
  else
    fail "Нет dev-инструментов" "найдено: $found"
  fi
fi

# 6 --------------------------------------------------------------- тесты
count
if [ "$SHELL_AVAILABLE" = "no" ]; then
  pass "Тесты не едут в образ" "шелла нет — проверять нечем"
else
  junk=$(in_image 'for p in /app/tests /app/.git /app/pyproject.toml; do [ -e $p ] && echo $p; done' | tr '\n' ' ')
  if [ -z "$junk" ]; then
    pass "Тесты и мусор не едут в образ"
  else
    fail "Тесты и мусор не едут в образ" "внутри: $junk"
  fi
fi

# 7 -------------------------------------------------------------- секреты
count
env_hit=$(docker image inspect -f '{{json .Config.Env}}' "$IMAGE" | grep -c 'ADMIN_TOKEN' || true)
hist_hit=$(docker history --no-trunc "$IMAGE" 2>/dev/null | grep -c 'ADMIN_TOKEN' || true)
if [ "$env_hit" -eq 0 ] && [ "$hist_hit" -eq 0 ]; then
  pass "Нет секретов в ENV и в истории"
elif [ "$env_hit" -eq 0 ]; then
  fail "Нет секретов в ENV и в истории" "из ENV убрали, но остался в history"
else
  fail "Нет секретов в ENV и в истории" "ADMIN_TOKEN в Config.Env"
fi

# 8 -------------------------------------------------------- .dockerignore
count
if [ -f .dockerignore ]; then
  pass ".dockerignore есть" "$(grep -cve '^\s*$' -e '^\s*#' .dockerignore) правил"
else
  fail ".dockerignore есть" "файла нет"
fi

# 9 ------------------------------------------------------------- hadolint
count
if command -v hadolint >/dev/null 2>&1; then
  # Порог warning, а не error: почти все претензии hadolint к плохому
  # Dockerfile — уровня warning, на уровне error он молчит.
  report=$(hadolint --no-color Dockerfile 2>/dev/null)
  errors=$(printf '%s\n' "$report" | grep -c 'error:' || true)
  warnings=$(printf '%s\n' "$report" | grep -c 'warning:' || true)
  if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ]; then
    pass "hadolint чист (>= warning)" "info: $(printf '%s\n' "$report" | grep -c 'info:' || true)"
  else
    fail "hadolint чист (>= warning)" "${errors} error, ${warnings} warning"
  fi
else
  fail "hadolint чист (>= warning)" "hadolint не установлен"
fi

echo
echo "  Готово: ${passed}/${total}"
echo

[ "$passed" -eq "$total" ]
