#!/usr/bin/env bash
# run-task.sh <project> <task-id> — autonomous build of ONE task via a headless
# architect/engineer loop (plan / build / review / fix) with a verification skill,
# in an isolated git worktree. Builds + commits locally on branch loop/<task>.
# NEVER pushes; stops at "ready to push" for human review.
#
# Config in config.json (see config.example.json); tasks in tasks/<project>.json.
#
# Push + draft-PR is a DELIBERATE human step after review:
#   git -C <repo> push -u origin loop/<task>
#   gh pr create --repo <remote> --base main --head loop/<task> --draft ...
set -uo pipefail
cd "$(dirname "$0")"
A="$(pwd)"
CONFIG="${AUTOBUILD_CONFIG:-config.json}"
WORKROOT="${AUTOBUILD_WORKROOT:-$A/.worktrees}"   # worktrees live OUTSIDE the target repo
BUDGET_CAP="${BUDGET_CAP:-20}"                    # cumulative USD across runs/
CLAUDE="${CLAUDE_BIN:-claude}"
ALLOWED="Bash,Read,Write,Edit,Glob,Grep,TodoWrite"
# Model tiering (pin per stage; never inherit): capable model for plan/review,
# a cheaper implementer model for build/fix. Override via env.
MODEL_PLAN="${AUTOBUILD_MODEL_PLAN:-claude-opus-4-8}"
MODEL_BUILD="${AUTOBUILD_MODEL_BUILD:-claude-sonnet-5}"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

PROJ="${1:?usage: run-task.sh <project> <task-id>}"
ID="${2:?usage: run-task.sh <project> <task-id>}"
cfg() { python3 -c "import json;print(json.load(open('$CONFIG'))['$PROJ']['$1'])"; }
REPO=$(cfg repo); PM=$(cfg package_manager); VERIFY=$(cfg verify); TPRE=$(cfg test_pass_regex)
TASK=$(python3 -c "import json;[print(json.dumps(t)) for t in json.load(open('tasks/$PROJ.json')) if t['id']=='$ID']")
[ -n "$TASK" ] || { echo "unknown task $ID in tasks/$PROJ.json"; exit 1; }
GOAL=$(echo "$TASK"|python3 -c "import json,sys;print(json.load(sys.stdin)['goal'])")
TVERIFY=$(echo "$TASK"|python3 -c "import json,sys;print(json.load(sys.stdin).get('verify','$VERIFY'))")
DONE=$(echo "$TASK"|python3 -c "import json,sys;print(json.load(sys.stdin)['done'])")

RUN="runs/$PROJ/$ID"; WT="$WORKROOT/$PROJ/$ID"; BR="loop/$ID"
mkdir -p "$RUN"
spend(){ find runs -name 'result-*.json' 2>/dev/null -exec cat {} \; \
  | python3 -c "import json,sys;print(round(sum(json.loads(l).get('total_cost_usd',0) for l in sys.stdin if l.strip()),2))" 2>/dev/null||echo 0; }
guard(){ local s;s=$(spend); if python3 -c "exit(0 if $s>=$BUDGET_CAP else 1)"; then
  echo ">>> BUDGET STOP: cumulative \$$s >= cap \$$BUDGET_CAP"; exit 9; fi; echo "    [budget] \$$s / \$$BUDGET_CAP"; }

# fresh worktree off main
git -C "$REPO" worktree remove --force "$WT" 2>/dev/null||true
git -C "$REPO" branch -D "$BR" 2>/dev/null||true
rm -rf "$WT"; mkdir -p "$(dirname "$WT")"
git -C "$REPO" worktree add -b "$BR" "$WT" main >"$RUN/worktree.log" 2>&1 || { echo "worktree add failed"; cat "$RUN/worktree.log"; exit 1; }
printf '# Task: %s\n\n## Goal\n%s\n\n## Verify\n```\n%s\n```\n\n## Done when\n%s\n' "$ID" "$GOAL" "$TVERIFY" "$DONE" >"$WT/TASK.md"
mkdir -p "$WT/.claude/skills/verification-before-completion"
cp skills/verification-before-completion/SKILL.md "$WT/.claude/skills/verification-before-completion/SKILL.md"

echo "=== $PROJ/$ID  branch=$BR ==="
echo "--- baseline ($PM) ---"
( cd "$WT" && eval "$VERIFY" ) >"$RUN/baseline.log" 2>&1 || true
BASE=$(grep -oE "$TPRE" "$RUN/baseline.log" | grep -oE "[0-9]+" | head -1)
[ -n "$BASE" ] || { echo "!! baseline not green — aborting (see $RUN/baseline.log)"; exit 2; }
echo "    baseline tests passing: $BASE"

stage(){ guard; echo "--- stage $1: $3 ($2) ---"
  ( cd "$WT" && "$CLAUDE" -p "$(cat "$A/kickoffs/$3")" --model "$2" \
      --output-format json --max-turns "$4" --allowedTools "$ALLOWED" ) >"$RUN/result-$1.json" 2>>"$RUN/stderr.log"
  echo "    stage $1 — \$$(python3 -c "import json;print('%.2f'%json.load(open('$RUN/result-$1.json')).get('total_cost_usd',0))" 2>/dev/null||echo '?')"; }
stage 1 "$MODEL_PLAN"  plan.md   40
stage 2 "$MODEL_BUILD" build.md 150
stage 3 "$MODEL_PLAN"  review.md 60
grep -q "VERDICT: CHANGES REQUIRED" "$WT/REVIEW.md" 2>/dev/null && stage 4 "$MODEL_BUILD" fix.md 100 || echo "--- stage 4 skipped (APPROVE) ---"

echo "=== independent verify ==="
( cd "$WT" && eval "$VERIFY" ) >"$RUN/verify.log" 2>&1; VOK=$?
VT=$(grep -oE "$TPRE" "$RUN/verify.log" | grep -oE "[0-9]+" | head -1)
echo; echo "===== $PROJ/$ID ====="
echo "branch:  $BR (NOT pushed) · commits: $(git -C "$WT" rev-list --count main..HEAD)"
echo "verify:  exit=$VOK tests=${VT:-?} (baseline $BASE) · review: $(grep -oE 'VERDICT: (APPROVE|CHANGES REQUIRED)' "$WT/REVIEW.md" 2>/dev/null|tail -1)"
echo "spend:   \$$(spend) / \$$BUDGET_CAP · worktree: $WT"
git -C "$WT" diff --stat main..HEAD | tail -15
{ [ "$VOK" = 0 ] && [ "$VT" = "$BASE" ]; } && echo "READY TO PUSH (human approval)" || echo "NOT READY — verify failed"
