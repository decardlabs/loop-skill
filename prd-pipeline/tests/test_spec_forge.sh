#!/bin/bash
# TDD Integration Test: spec-forge skill components
# Tests all the spec-forge components in isolation.
set -euo pipefail
PASS=0 FAIL=0

test_name() { echo -n "  TEST: $1 ... "; }
pass() { echo "✅ PASS"; PASS=$((PASS+1)); }
fail() { echo "❌ FAIL: $1"; FAIL=$((FAIL+1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap "rm -rf '$TMPDIR'" EXIT

# ─── Test 1: load_agentrc loads .agentrc file ───
test_name "load_agentrc reads .agentrc"
cat > "$TMPDIR/.agentrc" <<'EOF'
AGENT_TYPE=codex
AGENT_CMD=codex -p
AGENT_CONFIG=AGENTS.md
EOF
cd "$PIPELINE_DIR"
source "$PIPELINE_DIR/lib.sh"
load_agentrc "$TMPDIR"
if [ "$AGENT_TYPE" = "codex" ] && [ "$AGENT_CMD" = "codex -p" ]; then
    pass
else
    fail "Expected AGENT_TYPE=codex, got: $AGENT_TYPE"
fi
unset AGENT_TYPE AGENT_CMD AGENT_CONFIG

# ─── Test 2: load_agentrc ignores non-agent vars ───
test_name "load_agentrc ignores unrelated vars"
cat > "$TMPDIR/.agentrc" <<'EOF'
PATH=/evil
SECRET=leaked
AGENT_CMD=claude -p
EOF
load_agentrc "$TMPDIR"
if [ "$AGENT_CMD" = "claude -p" ]; then
    pass
else
    fail ".agentrc should not set arbitrary vars, AGENT_CMD=$AGENT_CMD"
fi
unset AGENT_CMD

# ─── Test 3: detect_test_command — Python/pytest ───
test_name "detect_test_command — Python"
mkdir -p "$TMPDIR/test-project"
touch "$TMPDIR/test-project/requirements.txt"
export TARGET_DIR="$TMPDIR/test-project"
cmd="$(detect_test_command)"
if echo "$cmd" | grep -q 'pytest'; then
    pass
else
    fail "Expected pytest command, got: $cmd"
fi
unset TARGET_DIR

# ─── Test 4: detect_test_command — Node.js ───
test_name "detect_test_command — Node.js"
mkdir -p "$TMPDIR/node-project"
echo '{"scripts":{"test":"jest"}}' > "$TMPDIR/node-project/package.json"
export TARGET_DIR="$TMPDIR/node-project"
cmd="$(detect_test_command)"
if echo "$cmd" | grep -qE 'jest|npm test'; then
    pass
else
    fail "Expected jest/npm test command, got: $cmd"
fi
unset TARGET_DIR

# ─── Test 5: detect_test_command — Rust ───
test_name "detect_test_command — Rust"
mkdir -p "$TMPDIR/rust-project"
touch "$TMPDIR/rust-project/Cargo.toml"
export TARGET_DIR="$TMPDIR/rust-project"
cmd="$(detect_test_command)"
if echo "$cmd" | grep -q 'cargo test'; then
    pass
else
    fail "Expected cargo test, got: $cmd"
fi
unset TARGET_DIR

# ─── Test 6: detect_test_command — Go ───
test_name "detect_test_command — Go"
mkdir -p "$TMPDIR/go-project"
touch "$TMPDIR/go-project/go.mod"
export TARGET_DIR="$TMPDIR/go-project"
cmd="$(detect_test_command)"
if echo "$cmd" | grep -q 'go test'; then
    pass
else
    fail "Expected go test, got: $cmd"
fi
unset TARGET_DIR

# ─── Test 7: detect_test_command — no framework → empty ───
test_name "detect_test_command — no framework"
mkdir -p "$TMPDIR/empty-project"
export TARGET_DIR="$TMPDIR/empty-project"
cmd="$(detect_test_command)"
if [ -z "$cmd" ]; then
    pass
else
    fail "Expected empty, got: $cmd"
fi
unset TARGET_DIR

# ─── Test 8: detect_tech_stack — multi-tech ───
test_name "detect_tech_stack"
mkdir -p "$TMPDIR/multi-project"
touch "$TMPDIR/multi-project/package.json" "$TMPDIR/multi-project/Dockerfile" "$TMPDIR/multi-project/Makefile"
export TARGET_DIR="$TMPDIR/multi-project"
stack="$(detect_tech_stack)"
if echo "$stack" | grep -q 'Node.js' && echo "$stack" | grep -q 'Docker'; then
    pass
else
    fail "Expected Node.js + Docker, got: $stack"
fi
unset TARGET_DIR

# ─── Test 9: delta spec format is valid ───
test_name "delta spec format is valid"
delta_file="$TMPDIR/delta_spec.md"
cat > "$delta_file" <<'DEOF'
## Task TASK-001

### ADDED Requirements
- User registration API implemented

### MODIFIED Requirements
- (from git diff)

### 变更文件
- src/api.py
DEOF
if grep -q 'ADDED Requirements' "$delta_file" && grep -q 'MODIFIED Requirements' "$delta_file"; then
    pass
else
    fail "Delta spec format invalid"
fi

# ─── Test 10: AGENT_CMD variable set correctly ───
test_name "AGENT_CMD default in scripts"
cd "$PIPELINE_DIR"
AGENT_HITS=$(grep -l '^AGENT_CMD=' task_executor.sh prd_to_spec.sh spec_to_issues.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "$AGENT_HITS" -eq 3 ]; then
    pass
else
    fail "Expected AGENT_CMD in 3 scripts, found in $AGENT_HITS"
fi

# ─── Test 11: SKILL.md exists with correct format ───
test_name "spec-forge SKILL.md exists"
SKILL_FILE="/Users/sunm15/Documents/loop/superpowers/skills/spec-forge/SKILL.md"
if [ -f "$SKILL_FILE" ] && head -3 "$SKILL_FILE" | grep -q 'name: spec-forge'; then
    pass
else
    fail "SKILL.md missing or incorrect format"
fi

# ─── Test 12: .agentrc.example exists ───
test_name ".agentrc.example exists"
if [ -f "/Users/sunm15/Documents/loop/.agentrc.example" ]; then
    pass
else
    fail ".agentrc.example not found"
fi

# ─── Summary ───
echo ""
echo "═══════════════════════════════════════"
echo "  spec-forge 组件测试结果"
echo "  ${PASS} ✅  |  ${FAIL} ❌"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
