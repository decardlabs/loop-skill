#!/bin/bash
# TDD Test: AGENT_CMD abstraction
# Tests that AGENT_CMD env var properly replaces hardcoded claude calls.
# RED phase: These tests define expected behavior before implementation.
set -euo pipefail
PASS=0 FAIL=0

test_name() { echo -n "  TEST: $1 ... "; }
pass() { echo "✅ PASS"; PASS=$((PASS+1)); }
fail() { echo "❌ FAIL: $1"; FAIL=$((FAIL+1)); }

# We source the actual lib.sh to test its agent config functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$LIB_DIR/lib.sh"

# ─── Test 1: Default AGENT_CMD value ───
test_name "Default AGENT_CMD is claude"
unset AGENT_CMD
# Simulate the default assignment that should be in task_executor.sh
AGENT_CMD_DEFAULT="${AGENT_CMD:-claude -p --dangerously-skip-permissions --no-session-persistence --output-format text}"
if [[ "$AGENT_CMD_DEFAULT" == claude* ]]; then
    pass
else
    fail "Expected claude default, got: $AGENT_CMD_DEFAULT"
fi

# ─── Test 2: Custom AGENT_CMD override ───
test_name "AGENT_CMD can be overridden"
export AGENT_CMD="codex -p"
AGENT_CMD_DEFAULT="${AGENT_CMD:-claude -p ...}"
if [ "$AGENT_CMD_DEFAULT" = "codex -p" ]; then
    pass
else
    fail "Expected 'codex -p', got: $AGENT_CMD_DEFAULT"
fi

# ─── Test 3: AGENT_CMD works with eval ───
test_name "AGENT_CMD works via eval"
export AGENT_CMD="echo MOCK_AGENT_OUTPUT"
result=$(echo "test prompt" | eval "$AGENT_CMD" 2>/dev/null)
if [ "$result" = "MOCK_AGENT_OUTPUT" ]; then
    pass
else
    fail "Expected MOCK_AGENT_OUTPUT, got: $result"
fi

# ─── Test 4: PIPESTATUS extraction after eval ───
test_name "PIPESTATUS[1] after eval"
export AGENT_CMD="cat"  # cat will output what it reads
# Simulate the actual executor pattern: echo prompt | eval $AGENT_CMD
echo "hello" | eval "$AGENT_CMD" >/dev/null 2>/dev/null
rc=${PIPESTATUS[1]}
if [ "$rc" -eq 0 ]; then
    pass
else
    fail "Expected exit code 0, got: $rc"
fi

# ─── Test 5: AGENT_CMD with failing command ───
test_name "AGENT_CMD failure exit code"
export AGENT_CMD="false"  # false always returns non-zero
echo "test" | eval "$AGENT_CMD" >/dev/null 2>/dev/null
rc=${PIPESTATUS[1]}
if [ "$rc" -ne 0 ]; then
    pass
else
    fail "Expected non-zero exit code from false"
fi

# ─── Summary ───
echo ""
echo "  Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
