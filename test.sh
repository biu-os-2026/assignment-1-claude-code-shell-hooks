#!/bin/bash
# =============================================================================
# Test Suite for Claude Code Hook System
# Tests each hook directly and through the runner.
# Usage: ./test.sh
# =============================================================================

# ── Colour codes ───────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/.claude/hooks/data"
HOOKS_DIR="$SCRIPT_DIR/.claude/hooks"
ORIG_CONF="$HOOKS_DIR/config/hooks.conf"

PASS=0
FAIL=0

# Ensure all hook scripts are executable
chmod +x "$HOOKS_DIR"/*.sh "$SCRIPT_DIR/hook_runner.sh" 2>/dev/null

# ── Helper functions ───────────────────────────────────────────────────────────

# reset_state: wipe runtime data to start each test section fresh
reset_state() {
    rm -rf "$DATA_DIR"
    mkdir -p "$DATA_DIR"
}

# assert_exit <expected> <actual> <test_name>
assert_exit() {
    local expected="$1"
    local actual="$2"
    local name="$3"
    if [ "$actual" -eq "$expected" ]; then
        printf '  %bPASS%b  %s\n' "$GREEN" "$RESET" "$name"
        PASS=$((PASS + 1))
    else
        printf '  %bFAIL%b   %s  (expected exit %d, got %d)\n' "$RED" "$RESET" "$name" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

# assert_output_contains <string> <output> <test_name>
assert_output_contains() {
    local needle="$1"
    local haystack="$2"
    local name="$3"
    if printf '%s' "$haystack" | grep -q "$needle"; then
        printf '  %bPASS%b  %s\n' "$GREEN" "$RESET" "$name"
        PASS=$((PASS + 1))
    else
        printf '  %bFAIL%b  %s  (expected to find: "%s")\n' "$RED" "$RESET" "$name" "$needle"
        printf '         Got: %s\n' "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

# make_bash_json <command> [session_id]
make_bash_json() {
    local cmd="$1"
    local sid="${2:-test-session-1}"
    # Escape backslashes and double-quotes in command for JSON embedding
    local escaped
    escaped="$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"session_id":"%s","cwd":"%s"}' \
        "$escaped" "$sid" "$SCRIPT_DIR"
}

# make_edit_json <file_path> [session_id]
make_edit_json() {
    local fp="$1"
    local sid="${2:-test-session-1}"
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"tool_response":{"filePath":"%s"},"session_id":"%s","cwd":"%s"}' \
        "$fp" "$fp" "$sid" "$SCRIPT_DIR"
}

# ══════════════════════════════════════════════════════════════════════════════
# Reset all config files to known-good values before tests run.
# This ensures student edits to config files don't break the test suite.
# ══════════════════════════════════════════════════════════════════════════════
CONFIG_DIR="$HOOKS_DIR/config"
mkdir -p "$CONFIG_DIR"

MAX_BACKUPS=5
cat > "$CONFIG_DIR/hooks.conf" <<EOF
# Rate Limiter 
MAX_COMMANDS=50
WARNING_THRESHOLD=40

# Auto Backup 
MAX_BACKUPS=$MAX_BACKUPS
EOF

cat > "$CONFIG_DIR/dangerous_patterns.txt" <<'EOF'
# Dangerous command patterns (regex format)
# Each line is a regex checked against the full command string
rm -rf
rm -r /
git reset --hard
git push.*--force
git push.*-f[^i]
> /dev/sd
mkfs\.
dd if=
:\(\)\{.*\};
chmod -R 777
EOF

cat > "$CONFIG_DIR/commit_prefixes.txt" <<'EOF'
feat
fix
docs
refactor
test
chore
EOF

cat > "$CONFIG_DIR/secret_files.txt" <<'EOF'
# Secret Files Blacklist
.env
folder/.env
EOF

cat > "$SCRIPT_DIR/hooks_config.txt" <<'EOF'
# Hook Runner Configuration
# Format: event_type:tool_matcher:script_path
# tool_matcher supports * wildcard (matches any tool name)
# Hooks run in order; first exit-2 stops the chain for PreToolUse
PreToolUse:Bash:./.claude/hooks/pre_command_firewall.sh
PreToolUse:Bash:./.claude/hooks/pre_rate_limiter.sh
PreToolUse:Bash:./.claude/hooks/pre_commit_validator.sh
PostToolUse:Edit:./.claude/hooks/post_auto_backup.sh
PostToolUse:Edit:./.claude/hooks/post_syntax_checker.sh
Stop:*:./.claude/hooks/post_session_summary.sh
EOF

# ══════════════════════════════════════════════════════════════════════════════
printf '\n%b════════════════════════════════════════════%b\n' "$BOLD" "$RESET"
printf '%b  Claude Code Hook System — Test Suite      %b\n' "$BOLD" "$RESET"
printf '%b════════════════════════════════════════════%b\n\n' "$BOLD" "$RESET"

# ══════════════════════════════════════════════════════════════════════════════
printf '%b── 1. Firewall Hook (direct) ────────────────%b\n' "$BOLD" "$RESET"
reset_state

FIREWALL="$HOOKS_DIR/pre_command_firewall.sh"

# PASS: safe command
make_bash_json "ls -la" | bash "$FIREWALL" > /dev/null 2>&1
assert_exit 0 $? "Safe command 'ls -la' should pass"

# PASS: non-Bash tool (should always pass)
printf '{"tool_name":"Edit","tool_input":{"file_path":"main.c"},"session_id":"s1"}' \
    | bash "$FIREWALL" > /dev/null 2>&1
assert_exit 0 $? "Non-Bash tool should pass without inspection"

# FAIL: dangerous 'rm -rf'
make_bash_json "rm -rf /home/user" | bash "$FIREWALL" > /dev/null 2>&1
assert_exit 2 $? "Dangerous 'rm -rf /home/user' should be blocked"

# FAIL: force push
make_bash_json "git push origin main --force" | bash "$FIREWALL" > /dev/null 2>&1
assert_exit 2 $? "Force push should be blocked"

# FAIL: chmod -R 777
make_bash_json "chmod -R 777 /etc" | bash "$FIREWALL" > /dev/null 2>&1
assert_exit 2 $? "'chmod -R 777' should be blocked"

# FAIL: git reset --hard
make_bash_json "git reset --hard HEAD~1" | bash "$FIREWALL" > /dev/null 2>&1
assert_exit 2 $? "'git reset --hard' should be blocked"

# Verify error message content
ERR_MSG="$(make_bash_json "rm -rf /tmp/x" | bash "$FIREWALL" 2>&1 1>/dev/null)"
assert_output_contains "BLOCKED" "$ERR_MSG" "Blocked message should contain 'BLOCKED'"

# ══════════════════════════════════════════════════════════════════════════════
printf '\n%b── 2. Rate Limiter Hook (direct) ────────────%b\n' "$BOLD" "$RESET"
reset_state

LIMITER="$HOOKS_DIR/pre_rate_limiter.sh"

# Run 3 commands under the default limit (50) — all should pass
make_bash_json "ls" "sess-rl-1" | bash "$LIMITER" > /dev/null 2>&1
assert_exit 0 $? "Command 1 of 50 should pass"
make_bash_json "pwd" "sess-rl-1" | bash "$LIMITER" > /dev/null 2>&1
assert_exit 0 $? "Command 2 of 50 should pass"
make_bash_json "echo hi" "sess-rl-1" | bash "$LIMITER" > /dev/null 2>&1
assert_exit 0 $? "Command 3 of 50 should pass"

# Patch config to test blocking and warning; restore on exit or error
BACKUP_CONF="$(mktemp)"
cp "$ORIG_CONF" "$BACKUP_CONF"
_restore_conf() { cp "$BACKUP_CONF" "$ORIG_CONF"; rm -f "$BACKUP_CONF"; }
trap '_restore_conf' EXIT

# MAX_COMMANDS=3, WARNING_THRESHOLD=2
printf 'MAX_COMMANDS=3\nWARNING_THRESHOLD=2\n' > "$ORIG_CONF"
reset_state

make_bash_json "ls"      "sess-rl-2" | bash "$LIMITER" > /dev/null 2>&1
assert_exit 0 $? "Command 1 of 3 (MAX=3) should pass"
make_bash_json "pwd"     "sess-rl-2" | bash "$LIMITER" > /dev/null 2>&1
assert_exit 0 $? "Command 2 of 3 (MAX=3) should pass"

# Command 3 is above WARNING_THRESHOLD(2) but at MAX(3) — still allowed
WARN_OUT="$(make_bash_json "echo third" "sess-rl-2" | bash "$LIMITER" 2>&1)"
assert_exit 0 $? "Command 3 of 3 (MAX=3, at limit) should pass with warning"
assert_output_contains "warning\|Warning\|WARNING\|limit\|approaching\|threshold" \
    "$WARN_OUT" "Command at warning threshold should emit a warning"

# Command 4 exceeds MAX_COMMANDS=3 — blocked
make_bash_json "echo 4th" "sess-rl-2" | bash "$LIMITER" > /dev/null 2>&1
assert_exit 2 $? "Command 4 when MAX=3 should be blocked"

# Check that a different session is independent
make_bash_json "ls" "sess-rl-other" | bash "$LIMITER" > /dev/null 2>&1
assert_exit 0 $? "Different session should start fresh"

# Reset mechanism: create .reset_commands, next command should pass even after limit
touch "$DATA_DIR/.reset_commands"
make_bash_json "ls" "sess-rl-2" | bash "$LIMITER" > /dev/null 2>&1
assert_exit 0 $? "After reset (.reset_commands), previously blocked session should pass"
if [ ! -f "$DATA_DIR/.reset_commands" ]; then
    printf '  %bPASS%b  .reset_commands file was removed after reset\n' "$GREEN" "$RESET"
    PASS=$((PASS + 1))
else
    printf '  %bFAIL%b  .reset_commands file should be removed after reset\n' "$RED" "$RESET"
    FAIL=$((FAIL + 1))
fi

# Restore original config and clear the trap
_restore_conf
trap - EXIT

# ══════════════════════════════════════════════════════════════════════════════
printf '\n%b── 3. Commit Validator Hook (direct) ────────%b\n' "$BOLD" "$RESET"
reset_state

VALIDATOR="$HOOKS_DIR/pre_commit_validator.sh"

# PASS: valid conventional commit (single quotes avoid JSON escaping issues)
make_bash_json "git commit -m 'feat: add login page'" | bash "$VALIDATOR" > /dev/null 2>&1
assert_exit 0 $? "Valid 'feat: add login page' should pass"

make_bash_json "git commit -m 'fix: correct off-by-one error'" | bash "$VALIDATOR" > /dev/null 2>&1
assert_exit 0 $? "Valid 'fix: correct off-by-one error' should pass"

# PASS: non-commit command
make_bash_json "ls -la" | bash "$VALIDATOR" > /dev/null 2>&1
assert_exit 0 $? "Non-commit command should pass"

# PASS: commit without -m (editor opens)
make_bash_json "git commit" | bash "$VALIDATOR" > /dev/null 2>&1
assert_exit 0 $? "Commit without -m should pass (editor-mode)"

# PASS: -am flag variant
make_bash_json "git commit -am 'feat: add user auth module'" | bash "$VALIDATOR" > /dev/null 2>&1
assert_exit 0 $? "Valid commit with '-am' flag should pass"

# PASS: -a -m flag variant
make_bash_json "git commit -a -m 'fix: handle null pointer case'" | bash "$VALIDATOR" > /dev/null 2>&1
assert_exit 0 $? "Valid commit with '-a -m' flags should pass"

# FAIL: missing prefix
BLOCK_OUT="$(make_bash_json "git commit -m 'added stuff'" | bash "$VALIDATOR" 2>&1)"
assert_exit 2 $? "Missing prefix 'added stuff' should be blocked"
assert_output_contains "Missing commit prefix. Based on your changes, try: 'feat: added stuff'" "$BLOCK_OUT" "Error should mention missing prefix"
assert_output_contains "Valid prefixes" "$BLOCK_OUT" "Error should list valid prefixes"

# FAIL: message too short (even with valid prefix the message is too short after prefix)
make_bash_json "git commit -m 'fix: bug'" | bash "$VALIDATOR" > /dev/null 2>&1
assert_exit 2 $? "Message 'fix: bug' (7 chars) is too short, should be blocked"

# FAIL: message too long (over 72 characters)
LONG_MSG="feat: this commit message is intentionally over seventy-two characters long"
make_bash_json "git commit -m '$LONG_MSG'" | bash "$VALIDATOR" > /dev/null 2>&1
assert_exit 2 $? "Message over 72 characters should be blocked"

# FAIL: message ends with period
make_bash_json "git commit -m 'feat: add user authentication.'" | bash "$VALIDATOR" > /dev/null 2>&1
assert_exit 2 $? "Message ending with period should be blocked"

# ══════════════════════════════════════════════════════════════════════════════
printf '\n%b── 4. Auto-Backup Hook (direct) ─────────────%b\n' "$BOLD" "$RESET"
reset_state

BACKUP_HOOK="$HOOKS_DIR/post_auto_backup.sh"

# Create a test file to back up
TEST_SRC="$(mktemp --suffix=.c)"
printf 'int main() { return 0; }\n' > "$TEST_SRC"

make_edit_json "$TEST_SRC" | bash "$BACKUP_HOOK" > /dev/null 2>&1
assert_exit 0 $? "Backup hook should always exit 0"

# Verify backup was created
BACKUP_COUNT="$(ls -1 "$DATA_DIR/.backups/"* 2>/dev/null | wc -l | tr -d ' ')"
if [ "$BACKUP_COUNT" -ge 1 ]; then
    printf '  %bPASS%b  Backup file was created (%d found)\n' "$GREEN" "$RESET" "$BACKUP_COUNT"
    PASS=$((PASS + 1))
else
    printf '  %bFAIL%b  No backup files found in %s/.backups/\n' "$RED" "$RESET" "$DATA_DIR"
    FAIL=$((FAIL + 1))
fi

# Verify session log contains a BACKUP entry
LOG_CONTENT="$(cat "$DATA_DIR/session_test-session-1.log" 2>/dev/null)"
assert_output_contains "BACKUP" "$LOG_CONTENT" "Session log should contain BACKUP entry"

# Non-existent file path should exit 0 (graceful no-op)
make_edit_json "/nonexistent/path/file.c" | bash "$BACKUP_HOOK" > /dev/null 2>&1
assert_exit 0 $? "Non-existent file path should exit 0 (no-op)"

# Test rotation: create MAX_BACKUPS+2 backups, check count stays at MAX_BACKUPS
BASE="$(basename "$TEST_SRC")"
for i in $(seq 1 $((MAX_BACKUPS + 2))); do
    sleep 1  # Ensure unique timestamps
    make_edit_json "$TEST_SRC" | bash "$BACKUP_HOOK" > /dev/null 2>&1
done
AFTER_ROTATE="$(ls -1 "$DATA_DIR/.backups/${BASE}."* 2>/dev/null | wc -l | tr -d ' ')"
if [ "$AFTER_ROTATE" -le "$MAX_BACKUPS" ]; then
    printf '  %bPASS%b  Rotation kept %d backups (MAX_BACKUPS=%d)\n' "$GREEN" "$RESET" "$AFTER_ROTATE" "$MAX_BACKUPS"
    PASS=$((PASS + 1))
else
    printf '  %bFAIL%b  Rotation failed: %d backups exist (expected ≤%d)\n' "$RED" "$RESET" "$AFTER_ROTATE" "$MAX_BACKUPS"
    FAIL=$((FAIL + 1))
fi
unset MAX_BACKUPS

rm -f "$TEST_SRC"

# ══════════════════════════════════════════════════════════════════════════════
printf '\n%b── 5. Syntax Checker Hook (direct) ──────────%b\n' "$BOLD" "$RESET"
reset_state

SYNTAX_HOOK="$HOOKS_DIR/post_syntax_checker.sh"

# Create a valid shell script
VALID_SH="$(mktemp --suffix=.sh)"
printf '#!/bin/bash\necho "hello world"\n' > "$VALID_SH"

OUT="$(make_edit_json "$VALID_SH" | bash "$SYNTAX_HOOK" 2>&1)"
assert_exit 0 $? "Valid .sh file should pass syntax check"
assert_output_contains "Syntax OK" "$OUT" "Output should say 'Syntax OK' for valid script"

# Create an invalid shell script
INVALID_SH="$(mktemp --suffix=.sh)"
printf '#!/bin/bash\nif [ -z "" \n  echo "unclosed"\n' > "$INVALID_SH"

make_edit_json "$INVALID_SH" | bash "$SYNTAX_HOOK" > /dev/null 2>&1
assert_exit 1 $? "Invalid .sh file should return exit 1 (warn)"

ERR_OUT="$(make_edit_json "$INVALID_SH" | bash "$SYNTAX_HOOK" 2>&1)"
assert_output_contains "SYNTAX ERROR" "$ERR_OUT" "Output should contain 'SYNTAX ERROR'"

# Log entries
LOG_CONTENT="$(cat "$DATA_DIR/session_test-session-1.log" 2>/dev/null)"
assert_output_contains "SYNTAX_OK" "$LOG_CONTENT" "Log should contain SYNTAX_OK entry"
assert_output_contains "SYNTAX_ERROR" "$LOG_CONTENT" "Log should contain SYNTAX_ERROR entry"

# Unknown extension — should pass silently
UNKNOWN_FILE="$(mktemp --suffix=.xyz)"
printf 'some content\n' > "$UNKNOWN_FILE"
make_edit_json "$UNKNOWN_FILE" | bash "$SYNTAX_HOOK" > /dev/null 2>&1
assert_exit 0 $? "Unknown extension should exit 0 (no checker available)"

# Non-existent file — should exit 0 (graceful no-op)
make_edit_json "/nonexistent/path/file.sh" | bash "$SYNTAX_HOOK" > /dev/null 2>&1
assert_exit 0 $? "Non-existent file should exit 0 (no-op)"

# Python syntax check (if python3 available)
if command -v python3 > /dev/null 2>&1; then
    VALID_PY="$(mktemp --suffix=.py)"
    printf 'def hello():\n    print("hello")\n' > "$VALID_PY"
    PY_OUT="$(make_edit_json "$VALID_PY" | bash "$SYNTAX_HOOK" 2>&1)"
    assert_exit 0 $? "Valid .py file should pass syntax check"
    assert_output_contains "Syntax OK" "$PY_OUT" "Output should say 'Syntax OK' for valid .py"

    INVALID_PY="$(mktemp --suffix=.py)"
    printf 'def hello(\n    print("unclosed")\n' > "$INVALID_PY"
    make_edit_json "$INVALID_PY" | bash "$SYNTAX_HOOK" > /dev/null 2>&1
    assert_exit 1 $? "Invalid .py file should return exit 1"

    rm -f "$VALID_PY" "$INVALID_PY"
else
    printf '  %bSKIP%b  python3 not found — skipping Python syntax tests\n' "$YELLOW" "$RESET"
fi

# C syntax check (if gcc available)
if command -v gcc > /dev/null 2>&1; then
    VALID_C="$(mktemp --suffix=.c)"
    printf '#include <stdio.h>\nint main() { return 0; }\n' > "$VALID_C"
    C_OUT="$(make_edit_json "$VALID_C" | bash "$SYNTAX_HOOK" 2>&1)"
    assert_exit 0 $? "Valid .c file should pass syntax check"
    assert_output_contains "Syntax OK" "$C_OUT" "Output should say 'Syntax OK' for valid .c"

    INVALID_C="$(mktemp --suffix=.c)"
    printf 'int main() { return\n' > "$INVALID_C"
    make_edit_json "$INVALID_C" | bash "$SYNTAX_HOOK" > /dev/null 2>&1
    assert_exit 1 $? "Invalid .c file should return exit 1"

    rm -f "$VALID_C" "$INVALID_C"
else
    printf '  %bSKIP%b  gcc not found — skipping C syntax tests\n' "$YELLOW" "$RESET"
fi

rm -f "$VALID_SH" "$INVALID_SH" "$UNKNOWN_FILE"

# ══════════════════════════════════════════════════════════════════════════════
printf '\n%b── 6. Session Summary Hook (direct) ─────────%b\n' "$BOLD" "$RESET"
reset_state

SUMMARY_HOOK="$HOOKS_DIR/post_session_summary.sh"

# Test: stop_hook_active=true should exit 0 immediately (no output)
OUT="$(printf '{"session_id":"s1","stop_hook_active":true}' | bash "$SUMMARY_HOOK" 2>&1)"
assert_exit 0 $? "stop_hook_active=true should exit 0 (loop guard)"
if [ -z "$OUT" ]; then
    printf '  %bPASS%b  stop_hook_active=true produced no output\n' "$GREEN" "$RESET"
    PASS=$((PASS + 1))
else
    printf '  %bFAIL%b  stop_hook_active=true produced unexpected output: %s\n' "$RED" "$RESET" "$OUT"
    FAIL=$((FAIL + 1))
fi

# Test: empty log → "No session activity recorded"
OUT="$(printf '{"session_id":"s1","stop_hook_active":false}' | bash "$SUMMARY_HOOK" 2>&1)"
assert_output_contains "No session activity" "$OUT" "Empty log should say 'No session activity recorded'"

# Pre-populate a realistic log
NOW_TS="$(date '+%Y-%m-%d %H:%M:%S')"
cat > "$DATA_DIR/session_test-session-abc.log" <<EOF
[$NOW_TS] BACKUP src/main.c -> $DATA_DIR/.backups/main.c.20240101_120000 (512 bytes)
[$NOW_TS] SYNTAX_OK src/main.c (c)
[$NOW_TS] BACKUP src/main.c -> $DATA_DIR/.backups/main.c.20240101_120001 (520 bytes)
[$NOW_TS] BACKUP src/utils.h -> $DATA_DIR/.backups/utils.h.20240101_120002 (128 bytes)
[$NOW_TS] SYNTAX_ERROR src/broken.c (c)
[$NOW_TS] SYNTAX_OK src/utils.h (c)
EOF

OUT="$(printf '{"session_id":"test-session-abc","stop_hook_active":false}' | bash "$SUMMARY_HOOK" 2>&1)"
assert_exit 0 $? "Session summary should always exit 0"
assert_output_contains "SESSION SUMMARY REPORT" "$OUT" "Output should contain report header"
assert_output_contains "test-session-abc" "$OUT" "Output should contain session ID"
assert_output_contains "Backups made" "$OUT" "Output should report backup count"
assert_output_contains "Syntax checks" "$OUT" "Output should report syntax check count"
assert_output_contains "Syntax errors" "$OUT" "Output should report syntax error count"
assert_output_contains "Total actions" "$OUT" "Output should report total action count"
assert_output_contains "main.c" "$OUT" "Output should list most-edited file"

# ══════════════════════════════════════════════════════════════════════════════
printf '\n%b── 7. Hook Runner (chain execution) ─────────%b\n' "$BOLD" "$RESET"
reset_state

RUNNER="$SCRIPT_DIR/hook_runner.sh"

# PASS chain: safe command through PreToolUse/Bash
OUT="$(make_bash_json "ls -la" | bash "$RUNNER" PreToolUse Bash 2>&1)"
assert_exit 0 $? "Safe command should pass all pre-hooks via runner"
assert_output_contains "Passed" "$OUT" "Runner output should show passes"
assert_output_contains "Matched:" "$OUT" "Runner output should include summary 'Matched:' line"

# BLOCK chain: dangerous command — should stop at firewall
OUT="$(make_bash_json "rm -rf /home" | bash "$RUNNER" PreToolUse Bash 2>&1)"
RC=$?
assert_exit 2 "$RC" "Dangerous command should be blocked via runner (exit 2)"
assert_output_contains "BLOCKED" "$OUT" "Runner output should show BLOCKED"
assert_output_contains "Chain stopped" "$OUT" "Runner output should indicate chain stopped"

# PASS: PostToolUse chain (Edit) — create a real file first
TEST_FILE="$(mktemp --suffix=.sh)"
printf '#!/bin/bash\necho ok\n' > "$TEST_FILE"
make_edit_json "$TEST_FILE" | bash "$RUNNER" PostToolUse Edit > /dev/null 2>&1
assert_exit 0 $? "Valid file edit should pass PostToolUse chain"
rm -f "$TEST_FILE"

# PASS: Stop event
printf '{"session_id":"runner-test","stop_hook_active":false}' \
    | bash "$RUNNER" Stop "*" > /dev/null 2>&1
assert_exit 0 $? "Stop event should pass via runner"

# Runner: missing arguments should print usage and exit non-zero
bash "$RUNNER" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    printf '  %b✓ PASS%b  Runner with no args exits non-zero\n' "$GREEN" "$RESET"
    PASS=$((PASS + 1))
else
    printf '  %bFAIL%b  Runner with no args should exit non-zero\n' "$RED" "$RESET"
    FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════════════════════════════
printf '\n%b────────────────────────────────────────────%b\n' "$BOLD" "$RESET"
TOTAL=$((PASS + FAIL))
printf '%bTest Results: %d / %d passed%b\n' "$BOLD" "$PASS" "$TOTAL" "$RESET"

if [ "$FAIL" -eq 0 ]; then
    printf '%bAll tests passed!%b\n\n' "$GREEN" "$RESET"
    exit 0
else
    printf '%b%d test(s) failed.%b\n\n' "$RED" "$FAIL" "$RESET"
    exit 1
fi