#!/usr/bin/env bash
# Smoke-проверка Launch Control: контейнер должен подняться и отвечать как раньше.
# Падает с ненулевым кодом при любой ошибке. Ручная проверка «вроде работает» не считается.
#
#   ./scripts/smoke.sh                        # launch-control:optimized
#   ./scripts/smoke.sh launch-control:step4-final
#   SMOKE_PORT=18001 ./scripts/smoke.sh ...
set -uo pipefail

IMAGE="${1:-launch-control:optimized}"
PORT="${SMOKE_PORT:-18000}"
BASE="http://127.0.0.1:${PORT}"
NAME="smoke-launch-control-$$"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() {
	printf '  \033[31m✗\033[0m %s\n' "$1"
	fail=1
}
check() { # <описание> <ожидаемое> <фактическое>
	if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1: ожидали '$2', получили '$3'"; fi
}

code() { curl -s -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || echo "000"; }

echo
echo "=== smoke: $IMAGE (порт $PORT) ==="

if ! docker run -d --name "$NAME" -p "127.0.0.1:${PORT}:8000" "$IMAGE" >/dev/null 2>&1; then
	echo "  не удалось запустить контейнер (порт занят?)"
	exit 1
fi

# Готовность: до 30 секунд, без фиксированного sleep.
ready=0
for _ in $(seq 1 30); do
	[ "$(code "$BASE/health")" = "200" ] && {
		ready=1
		break
	}
	sleep 1
done
if [ "$ready" -ne 1 ]; then
	echo "  сервис не ответил на /health за 30 с"
	docker logs "$NAME" 2>&1 | tail -20
	exit 1
fi

check "GET /health -> 200" "200" "$(code "$BASE/health")"
check "GET /health: status=ok" "ok" "$(curl -s "$BASE/health" | jq -r '.status // "null"')"

check "GET /api/v1/launches -> 200" "200" "$(code "$BASE/api/v1/launches")"
check "GET /api/v1/launches: 5 миссий" "5" "$(curl -s "$BASE/api/v1/launches" | jq 'length')"
check "есть LC-101" "LC-101" "$(curl -s "$BASE/api/v1/launches" | jq -r '[.[].id] | index("LC-101") | if . == null then "нет" else "LC-101" end')"

cd101="$(curl -s -X POST "$BASE/api/v1/launches/LC-101/countdown")"
check "POST LC-101/countdown -> 200" "200" "$(code -X POST "$BASE/api/v1/launches/LC-101/countdown")"
check "LC-101: status=counting" "counting" "$(printf '%s' "$cd101" | jq -r '.status // "null"')"
check "LC-101: t_minus_seconds=600" "600" "$(printf '%s' "$cd101" | jq -r '.t_minus_seconds // "null"')"

check "POST LC-102/countdown -> 409" "409" "$(code -X POST "$BASE/api/v1/launches/LC-102/countdown")"
check "GET /api/v1/launches/LC-999 -> 404" "404" "$(code "$BASE/api/v1/launches/LC-999")"

check "контейнер остался running" "true" "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || echo "нет")"

echo
if [ "$fail" -ne 0 ]; then
	echo "SMOKE FAILED"
	exit 1
fi
echo "SMOKE OK"
