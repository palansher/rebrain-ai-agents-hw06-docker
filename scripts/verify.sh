#!/usr/bin/env bash
# Независимая приёмка. Запускает ЧЕЛОВЕК, не агент.
# Проверяет финальный образ и репозиторий по критериям задания.
#
#   ./scripts/verify.sh              # launch-control:optimized
#   ./scripts/verify.sh step4-final  # другой тег
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TAG="${1:-optimized}"
IMAGE="launch-control:${TAG}"
fails=0

ok() { printf '  \033[32m[PASS]\033[0m %s\n' "$1"; }
bad() {
	printf '  \033[31m[FAIL]\033[0m %s\n' "$1"
	fails=$((fails + 1))
}
run() {
	local desc="$1"
	shift
	if "$@" >/tmp/verify-step.log 2>&1; then ok "$desc"; else
		bad "$desc"
		sed -n '1,15p' /tmp/verify-step.log
	fi
}

echo
echo "=== независимая приёмка: $IMAGE ==="

run "образ существует" docker image inspect "$IMAGE"
run "score.sh = 9/9" ./scripts/score.sh "$TAG"
run "hadolint без error/warning" hadolint --no-color Dockerfile
run "smoke: поведение не сломано" ./scripts/smoke.sh "$IMAGE"
run "тесты: uv run --frozen --extra dev pytest" uv run --frozen --extra dev pytest -q

size_mb=$(($(docker image inspect -f '{{.Size}}' "$IMAGE" 2>/dev/null || echo 0) / 1000 / 1000))
if [ "$size_mb" -gt 0 ] && [ "$size_mb" -le 400 ]; then ok "размер ${size_mb} MB <= 400 MB"; else bad "размер ${size_mb} MB"; fi

user=$(docker image inspect -f '{{.Config.User}}' "$IMAGE" 2>/dev/null || true)
if [ -n "$user" ] && [ "$user" != "root" ] && [ "$user" != "0" ]; then ok "non-root: $user"; else bad "non-root: '${user:-root}'"; fi

if [ -n "$(docker image inspect -f '{{if .Config.Healthcheck}}yes{{end}}' "$IMAGE" 2>/dev/null)" ]; then ok "HEALTHCHECK есть"; else bad "HEALTHCHECK нет"; fi

if docker history --no-trunc "$IMAGE" 2>/dev/null | grep -q 'ADMIN_TOKEN'; then bad "ADMIN_TOKEN в history"; else ok "ADMIN_TOKEN в history отсутствует"; fi

if docker run --rm --entrypoint sh "$IMAGE" -c 'test ! -e /app/tests && test ! -e /app/pyproject.toml && test ! -e /app/.git' >/dev/null 2>&1; then
	ok "тестов, pyproject и .git в образе нет"
else
	bad "в образе есть тесты/pyproject/.git (или нет sh — проверь вручную)"
fi

if git diff --quiet baseline..HEAD -- app tests tools; then ok "app/, tests/, tools/ не изменены"; else bad "app/, tests/, tools/ изменены"; fi

if grep -q 'vs-nexus' uv.lock 2>/dev/null; then bad "uv.lock содержит внутренний индекс"; else ok "uv.lock без внутренних registry"; fi

echo
if [ "$fails" -ne 0 ]; then
	echo "ПРИЁМКА НЕ ПРОЙДЕНА: $fails проверок с ошибкой"
	exit 1
fi
echo "ПРИЁМКА ПРОЙДЕНА: все проверки зелёные"
