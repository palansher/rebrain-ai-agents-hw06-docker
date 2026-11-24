#!/usr/bin/env bash
# Замер четырёх метрик упаковки. Результат дописывается в bench-results.md.
#
#   ./scripts/bench.sh baseline     — снять baseline на текущем Dockerfile
#   ./scripts/bench.sh after-agent  — снять замер после правок агента
#
# Четвёртая метрика — тёплая пересборка — единственная, которую не видит
# ни размер образа, ни hadolint. Скрипт мерит её честно: сам дописывает
# строку в app/main.py, пересобирает, замеряет и откатывает правку.
set -euo pipefail

TAG="${1:-baseline}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IMAGE="launch-control:${TAG}"
RESULTS="bench-results.md"
TOUCHED="app/main.py"

cleanup() {
  if [ -n "${BACKUP:-}" ] && [ -f "$BACKUP" ]; then
    cp "$BACKUP" "$TOUCHED"
    rm -f "$BACKUP"
    echo "  правка в $TOUCHED откачена"
  fi
}
trap cleanup EXIT

secs() { date +%s; }

human_mb() { echo $(( $1 / 1000 / 1000 )); }

echo
echo "=== bench: $IMAGE ==="
echo

# ---------------------------------------------------------------- 1. холодная
echo "[1/3] холодная сборка (--no-cache) — это долго, так и задумано"
start=$(secs)
if ! docker build --no-cache -t "$IMAGE" . >/tmp/bench-cold.log 2>&1; then
  echo "  СБОРКА УПАЛА. Хвост лога:"
  tail -n 30 /tmp/bench-cold.log
  exit 1
fi
cold=$(( $(secs) - start ))
echo "  ${cold}s"

# ------------------------------------------------------------------ 2. размер
size_bytes=$(docker image inspect -f '{{.Size}}' "$IMAGE")
size_mb=$(human_mb "$size_bytes")
total_layers=$(docker history -q "$IMAGE" | wc -l | tr -d ' ')
echo "[2/3] размер ${size_mb} MB, слоёв в истории: ${total_layers}"

# ------------------------------------------------------------------- 3. тёплая
echo "[3/3] тёплая пересборка после правки одной строки в $TOUCHED"
BACKUP="$(mktemp)"
cp "$TOUCHED" "$BACKUP"
printf '\n# bench touch: %s\n' "$TAG" >>"$TOUCHED"

start=$(secs)
if ! docker build -t "${IMAGE}-warm" . >/tmp/bench-warm.log 2>&1; then
  echo "  ПЕРЕСБОРКА УПАЛА. Хвост лога:"
  tail -n 30 /tmp/bench-warm.log
  exit 1
fi
warm=$(( $(secs) - start ))
echo "  ${warm}s"

docker image rm -f "${IMAGE}-warm" >/dev/null 2>&1 || true

# ------------------------------------------------------------------- 4. слои
top_layers=$(docker history --no-trunc --format '{{.Size}}|{{.CreatedBy}}' "$IMAGE" \
  | head -n 40 \
  | awk -F'|' '$1 !~ /^0B$/ {printf "%-10s %s\n", $1, substr($2,1,70)}' \
  | head -n 5)

# ------------------------------------------------------------------- отчёт
{
  echo
  echo "## ${TAG}"
  echo
  echo "| Метрика | Значение |"
  echo "| --- | --- |"
  echo "| Размер образа | ${size_mb} MB |"
  echo "| Холодная сборка | ${cold} s |"
  echo "| **Тёплая пересборка** | **${warm} s** |"
  echo "| Слоёв в истории | ${total_layers} |"
  echo
  echo "Самые тяжёлые шаги:"
  echo
  echo '```'
  echo "$top_layers"
  echo '```'
} >>"$RESULTS"

echo
echo "--------------------------------------------------"
printf '  Размер образа        %s MB\n' "$size_mb"
printf '  Холодная сборка      %s s\n'  "$cold"
printf '  Тёплая пересборка    %s s   <- вот эта\n' "$warm"
printf '  Слоёв в истории      %s\n'    "$total_layers"
echo "--------------------------------------------------"
echo
echo "Дописано в $RESULTS"
echo "Дальше: ./scripts/score.sh ${TAG}"
echo
