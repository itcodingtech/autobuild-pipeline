#!/usr/bin/env bash
# triage.sh <project> — classify a project's backlog into buildable task specs
# (tasks/<project>-auto.json) + escalations (escalations/<project>.json).
# Read-only over the target repo; writes only into this tool dir.
set -uo pipefail
cd "$(dirname "$0")"
A="$(pwd)"
CONFIG="${AUTOBUILD_CONFIG:-config.json}"
CLAUDE="${CLAUDE_BIN:-claude}"
MODEL="${AUTOBUILD_MODEL_TRIAGE:-claude-sonnet-5}"
PROJ="${1:?usage: triage.sh <project>}"
cfg(){ python3 -c "import json;print(json.load(open('$CONFIG'))['$PROJ'].get('$1',''))"; }
REPO=$(cfg repo); VERIFY=$(cfg verify); BACKLOG=$(cfg backlog)
[ -n "$REPO" ] || { echo "unknown project $PROJ"; exit 1; }

BRANCHES=$(git -C "$REPO" branch --list 'loop/*' | tr -d ' +*' | paste -sd, -)
WORK="$A/.triage/$PROJ"; rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

PROMPT="$(cat "$A/kickoffs/triage.md")

CONTEXT
- Repo: $REPO   (read files with absolute paths; do NOT modify anything in the repo)
- Backlog file: $REPO/$BACKLOG
- Project verify command (use verbatim as each task's \"verify\"): $VERIFY
- Existing branches already covering work (classify matching items as DONE): ${BRANCHES:-none}
"
echo "=== triage $PROJ (reading $REPO/$BACKLOG) ==="
"$CLAUDE" -p "$PROMPT" --model "$MODEL" --output-format json --max-turns 40 \
  --allowedTools "Read,Grep,Glob,Write" > result.json 2> stderr.log

COST=$(python3 -c "import json;print('%.2f'%json.load(open('result.json')).get('total_cost_usd',0))" 2>/dev/null||echo '?')
[ -f tasks-auto.json ] || { echo "!! triage produced no tasks-auto.json (see $WORK)"; exit 2; }
mkdir -p "$A/tasks" "$A/escalations"
cp tasks-auto.json "$A/tasks/$PROJ-auto.json"
[ -f escalations.json ] && cp escalations.json "$A/escalations/$PROJ.json"
NB=$(python3 -c "import json;print(len(json.load(open('tasks-auto.json'))))" 2>/dev/null||echo '?')
NE=$(python3 -c "import json;print(len(json.load(open('escalations.json'))))" 2>/dev/null||echo 0)
echo "triage done — \$$COST · buildable=$NB · escalated=$NE"
echo "  -> tasks/$PROJ-auto.json   escalations/$PROJ.json"
