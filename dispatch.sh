#!/usr/bin/env bash
# dispatch.sh <project> — SHADOW-MODE autonomous batch: auto-pick buildable tasks from
# tasks/<project>-auto.json and build each via run-task.sh, up to MAX_TASKS / BUDGET_CAP.
# Builds + verifies + STOPS at ready-to-push (never pushes, never merges). Appends a
# run-log line per task. Human reviews + pushes + merges the queued branches afterward.
set -uo pipefail
cd "$(dirname "$0")"
A="$(pwd)"
PROJ="${1:?usage: dispatch.sh <project>}"
MAX_TASKS="${MAX_TASKS:-4}"
BUDGET_CAP="${BUDGET_CAP:-20}"; export BUDGET_CAP
REPO=$(python3 -c "import json;print(json.load(open('config.json'))['$PROJ']['repo'])")
AUTO="tasks/$PROJ-auto.json"
[ -f "$AUTO" ] || { echo "no $AUTO — run ./triage.sh $PROJ first"; exit 1; }

LOG="runs/$PROJ/dispatch-log.jsonl"; mkdir -p "runs/$PROJ"
spend(){ find runs -name 'result-*.json' 2>/dev/null -exec cat {} \; \
  | python3 -c "import json,sys;print(round(sum(json.loads(l).get('total_cost_usd',0) for l in sys.stdin if l.strip()),2))" 2>/dev/null||echo 0; }

# ids to build: first MAX_TASKS from the auto list that don't already have a loop/ branch
mapfile -t IDS < <(python3 -c "import json;[print(t['id']) for t in json.load(open('$AUTO'))]")
echo "=== dispatch $PROJ · queue ${#IDS[@]} buildable · MAX_TASKS=$MAX_TASKS · BUDGET_CAP=\$$BUDGET_CAP ==="
built=0; queued=(); skipped=(); failed=()
for id in "${IDS[@]}"; do
  [ "$built" -ge "$MAX_TASKS" ] && { echo "-- MAX_TASKS reached --"; break; }
  s=$(spend); python3 -c "exit(0 if $s>=$BUDGET_CAP else 1)" && { echo "-- BUDGET_CAP reached (\$$s) --"; break; }
  if git -C "$REPO" show-ref --verify --quiet "refs/heads/loop/$id"; then
    echo "  skip $id (branch exists)"; skipped+=("$id"); continue; fi
  echo; echo ">>> building $id  (spend \$$s / \$$BUDGET_CAP)"
  mkdir -p "runs/$PROJ/$id"   # must exist before the redirect below, else run-task.sh never launches
  # ensure this task is in tasks/<project>.json for run-task.sh (merge auto list)
  python3 - "$AUTO" "tasks/$PROJ.json" <<'PY'
import json,sys,os
auto=json.load(open(sys.argv[1])); dst=sys.argv[2]
cur=json.load(open(dst)) if os.path.exists(dst) else []
ids={t['id'] for t in cur}
cur+=[t for t in auto if t['id'] not in ids]
json.dump(cur,open(dst,'w'),indent=2)
PY
  if ./run-task.sh "$PROJ" "$id" > "runs/$PROJ/$id/dispatch.out" 2>&1; then
    tail -6 "runs/$PROJ/$id/dispatch.out" | sed 's/^/    /'
    if grep -q "READY TO PUSH" "runs/$PROJ/$id/dispatch.out"; then st=ready; queued+=("$id"); else st=notready; failed+=("$id"); fi
  else st=error; failed+=("$id"); echo "    run-task.sh errored (see dispatch.out)"; fi
  c=$(python3 -c "import glob,json;print(round(sum(json.load(open(f)).get('total_cost_usd',0) for f in glob.glob('runs/$PROJ/$id/result-*.json')),2))" 2>/dev/null||echo '?')
  tests=$(grep -oE "verify: +exit=[0-9]+ tests=[0-9]+" "runs/$PROJ/$id/dispatch.out" | tail -1)
  printf '{"project":"%s","task":"%s","status":"%s","cost":%s,"detail":"%s"}\n' "$PROJ" "$id" "$st" "${c:-0}" "$tests" >> "$LOG"
  built=$((built+1))
done

echo; echo "===== DISPATCH SUMMARY: $PROJ ====="
echo "built:    $built   spend: \$$(spend) / \$$BUDGET_CAP"
echo "READY (queued for your push+PR): ${queued[*]:-none}"
echo "skipped (already have a branch):  ${skipped[*]:-none}"
echo "NOT ready (needs a look):         ${failed[*]:-none}"
echo "run-log: $LOG"