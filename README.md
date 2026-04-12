# OS Course 2026 — Exercise 1: Claude Code Shell Hooks

| | |
|---|---|
| **Deadline** | May 5 23:59, 2026 |
| **Submission** | GitHub Classroom — your code is tested automatically on every push |
| **Type** | Solo assignment |
| **Language** | Bash only |
| **TA** | Einat Noyman |
| **Questions** | Course forum: https://lemida.biu.ac.il/mod/forum/view.php?id=3058210 |
| **Deadline extensions** | Email os.biu.2026@gmail.com (see details below) |

> **⚠️ Please read ALL instructions carefully before starting to code.**

> **Can't find your name in the GitHub Classroom?** If you don't see your name on the exercise classroom welcome board, contact us immediately for help.

> **Running on Windows (WSL/Git Bash)?** If you get errors like `\r: command not found` or `bad interpreter`, run this command once after cloning:
> ```bash
> dos2unix test.sh hook_runner.sh .claude/hooks/*.sh
> ```
> This converts Windows-style line endings (CRLF) to Unix format (LF). Install with `sudo apt install dos2unix` if needed.

### Submission details

Your submission is the code you push to your GitHub Classroom repository. **Tests run automatically on every push** — make sure all tests pass before the deadline.

### Deadline extensions

If you need extra time, email **os.biu.2026@gmail.com** with:
- Your **GitHub username**
- How many **extra days** you are requesting
- A brief reason

Don't worry — we are nice. If you have a good reason, you will get the extension. **Requests not answered by 2 days before the submission date are automatically accepted.**

### Questions and help

We strongly encourage you to ask questions on the course forum: https://lemida.biu.ac.il/mod/forum/view.php?id=3058210

Help each other! If you see a question you can answer, go ahead. We will make sure every question gets answered.

---

## 1. Introduction

**Claude Code** is an AI-powered coding assistant by Anthropic that runs directly in your terminal. It can read and edit files, run shell commands, manage Git, and autonomously complete multi-step coding tasks. Read more: https://docs.anthropic.com/en/docs/claude-code/overview

**Hooks** are user-defined shell scripts that plug into Claude Code's lifecycle. They run automatically at specific points:

- **PreToolUse** — runs *before* Claude executes a tool (e.g., before running a Bash command). A hook can **block** the action by exiting with code `2`.
- **PostToolUse** — runs *after* Claude uses a tool (e.g., after editing a file). Used for monitoring, logging, or side effects.
- **Stop** — runs when a Claude Code session ends. Used for reporting or cleanup.

Hooks receive a JSON payload on `stdin` and communicate through exit codes. Read more: https://docs.anthropic.com/en/docs/claude-code/hooks

**What you will build:** A complete hook system — 6 hooks and a runner — that guards, monitors, and enhances an AI coding assistant. Along the way you will practice the core Bash skills that every systems programmer needs: text processing, file I/O, process control, and exit code handling — all through a real, working framework.

> **No Claude Code subscription required.** The hooks are plain Bash scripts that read from `stdin` and write to `stdout`/`stderr`. The provided `hook_runner.sh` simulates the hook execution environment. If you *do* have Claude Code access, see the **Bonus** section at the end for how to wire your hooks into a real project.

---

## 2. The Big Picture

### What you are building

```
 Claude Code (or hook_runner.sh for testing)
       │
       │  JSON payload on stdin
       ▼
 ┌─────────────────────────────────────────┐
 │           PreToolUse hooks              │  ← Run BEFORE action
 │  1. pre_command_firewall.sh  (block?)   │    Exit 2 = BLOCK
 │  2. pre_rate_limiter.sh      (block?)   │    Exit 0 = allow
 │  3. pre_commit_validator.sh  (block?)   │
 └─────────────────────────────────────────┘
       │ (if all pass)
       ▼
   Claude executes the action
       │
       ▼
 ┌─────────────────────────────────────────┐
 │       PostToolUse / Stop hooks          │  ← Run AFTER action
 │  4. post_auto_backup.sh                 │    Always exit 0
 │  5. post_syntax_checker.sh              │    (post-hooks never block)
 │  6. post_session_summary.sh (Stop)      │
 └─────────────────────────────────────────┘
```

### Communication model

```
stdin (JSON)  →  hook script  →  exit code (decision)
                              →  stderr   (error/warning messages)
                              →  stdout   (informational output)
```

### Exit codes

| Exit code | Meaning |
|-----------|---------|
| `0` | Allow / success |
| `2` | **BLOCK** the action — PreToolUse only. Print reason to `stderr`. |
| `1` | Warning (non-fatal) — continue but report |
| Any other non-zero | Error — continue but report |

### Project structure

This is the folder structure you receive. You must implement all files marked with **IMPLEMENT**.

```
├── hook_runner.sh                        ← IMPLEMENT (starter template provided)
├── hooks_config.txt                      ← PROVIDED — (example — may change in tests)
├── test.sh                               ← PROVIDED — automated tests run on every push
├── .env                                  ← PROVIDED — example secret file used by pre_secrets_guard.sh demo
├── .claude/
│   ├── settings.json                     ← PROVIDED (for optional Claude Code integration)
│   └── hooks/
│       ├── pre_command_firewall.sh       ← IMPLEMENT
│       ├── pre_rate_limiter.sh           ← IMPLEMENT
│       ├── pre_commit_validator.sh       ← IMPLEMENT
│       ├── post_auto_backup.sh           ← IMPLEMENT
│       ├── post_syntax_checker.sh        ← IMPLEMENT
│       ├── post_session_summary.sh       ← IMPLEMENT
│       ├── pre_secrets_guard.sh          ← PROVIDED — fully implemented demo (study this!)
│       ├── config/
│       │   ├── dangerous_patterns.txt    ← PROVIDED (example — may change in tests)
│       │   ├── hooks.conf                ← PROVIDED (example — may change in tests)
│       │   ├── commit_prefixes.txt       ← PROVIDED (example — may change in tests)
│       │   └── secret_files.txt          ← PROVIDED (example — may change in tests)
│       └── data/
│           └── session_test-session-1.log  ← PROVIDED (sample log for testing)
```

**Summary:** You implement **7 files** — 6 hook scripts + `hook_runner.sh`.

> **🚫 No `jq`!** All JSON parsing must use basic Bash tools only (`grep`, `sed`, `awk`, `cut`, etc.). This is intentional — practicing core text processing is a key goal of this exercise. Submissions using `jq` will fail the automated tests.

**Important:** The configuration files provided are **examples only**. During automated testing, these files may contain different values, different patterns, or a different number of entries. Your code must handle any valid configuration — do not hardcode values from the example files.

---

## 3. The Hook Runner

`hook_runner.sh` is your test harness. It simulates exactly how Claude Code executes hooks, so you can test everything without needing Claude Code itself.

### Usage

```bash
echo '<json>' | ./hook_runner.sh <event_type> <tool_name>
```

- `event_type`: `PreToolUse`, `PostToolUse`, or `Stop`
- `tool_name`: the tool being used, e.g., `Bash`, `Edit`, `Write`, `*`

### Example 1 — safe command passes all pre-hooks

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"s1"}' \
    | ./hook_runner.sh PreToolUse Bash
```

Expected output:
```
─── Hook Runner (PreToolUse / Bash) ───
▶ Running: ./.claude/hooks/pre_command_firewall.sh
  ✓ Passed
▶ Running: ./.claude/hooks/pre_rate_limiter.sh
  ✓ Passed
▶ Running: ./.claude/hooks/pre_commit_validator.sh
  ✓ Passed

─── Hook Execution Summary ──────────
Matched:  3 hooks
Passed:   3
Blocked:  0
Warnings: 0
```

### Example 2 — dangerous command gets blocked

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"session_id":"s1"}' \
    | ./hook_runner.sh PreToolUse Bash
```

Expected output:
```
─── Hook Runner (PreToolUse / Bash) ───
▶ Running: ./.claude/hooks/pre_command_firewall.sh
  ✗ BLOCKED
  BLOCKED: Command matches dangerous pattern 'rm -rf'. Please use a safer alternative.
[Chain stopped — hook returned exit 2]

─── Hook Execution Summary ──────────
Matched:  3 hooks
Passed:   0
Blocked:  1
Warnings: 0
```

### How the runner works

The runner reads `hooks_config.txt` to discover which scripts to run for a given event and tool:

```
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
```

- `tool_matcher` can be an exact tool name (`Bash`, `Edit`) or `*` to match any tool.
- Hooks run in the order they appear in the config.
- For `PreToolUse`, the chain stops immediately on the first exit code `2`.

### What you need to implement in the runner

1. **Read arguments** — `event_type` from `$1`, `tool_name` from `$2`. Print usage and exit if either is missing.
2. **Save stdin** — stdin can only be read once, but multiple hooks all need the same JSON. Save it to a temp file immediately. Use `trap 'rm -f "$TEMP"' EXIT` to clean up.
3. **Parse the config file** — skip comment lines (`#`) and blank lines. Split each line on `:` to get event, matcher, and script path.
4. **Match** — run a hook only if its event matches `$1` AND its matcher matches `$2` (exact match) or is `*`.
5. **Execute each matched hook** — pipe the saved JSON into the script. Capture `stderr` separately. Print `✓ Passed`, `✗ BLOCKED`, or `⚠ Warning` based on exit code.
6. **Stop on block** — if a hook exits `2`, print the chain-stopped message and break the loop.
7. **Print a summary** — total matched, passed, blocked, and warnings.

---

## 4. Walkthrough — Learning by Example

Before implementing anything, study the demo hook `pre_secrets_guard.sh`. This is a fully working hook — understanding it gives you the pattern you will repeat for all 6 hooks.

### Full source code

```bash
#!/bin/bash
# =============================================================================
# Pre-Hook: Secrets Guard
# Purpose:    Block Claude Code from reading files listed in secret_files.txt.
# Input:      JSON on stdin: {"tool_name":"Read","tool_input":{"file_path":"..."},...}
# Exit codes: 0 = allow, 2 = block (file is secret)
# =============================================================================

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/secret_files.txt"

# Read entire JSON input from stdin
INPUT="$(cat)"

# Extract file_path from tool_input
FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')"

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Normalize: convert backslashes to forward slashes, lowercase for comparison
normalize() {
    printf '%s' "$1" | tr '\\' '/' | tr '[:upper:]' '[:lower:]'
}

NORMALIZED_PATH="$(normalize "$FILE_PATH")"

# Check config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

# Check file path against each entry in the blacklist
while IFS= read -r entry; do
    # Skip comments and empty lines
    case "$entry" in
        '#'*|'') continue ;;
    esac

    NORMALIZED_ENTRY="$(normalize "$entry")"

    # Block if the file path ends with the blacklist entry (suffix match)
    case "$NORMALIZED_PATH" in
        *"$NORMALIZED_ENTRY")
            printf "BLOCKED: Reading '%s' is not allowed (matches secret file rule '%s').\n" "$FILE_PATH" "$entry" >&2
            exit 2
            ;;
    esac
done < "$CONFIG_FILE"

exit 0
```

### Step-by-step breakdown

**1. Path resolution**
```bash
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/secret_files.txt"
```
This finds the directory where the hook script lives, regardless of where you run it from. All config and data paths are relative to this directory. You must use this pattern in every hook.

**2. Reading stdin**
```bash
INPUT="$(cat)"
```
`cat` with no arguments reads from stdin. This captures the entire JSON payload into a variable. Do this once at the top — after this line, stdin is consumed and cannot be read again.

**3. Extracting a JSON field with grep/sed**
```bash
FILE_PATH="$(printf '%s' "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')"
```
- `grep -o '"file_path":"[^"]*"'` — finds the key-value pair in the JSON
- `head -1` — takes only the first match (safety measure)
- `sed 's/"file_path":"//;s/"//'` — strips the key and quotes, leaving just the value

**4. Reading a config file, skipping comments**
```bash
while IFS= read -r line; do
    case "$line" in
        '#'*|'') continue ;;
    esac
    # ... use $line
done < "$CONFIG_FILE"
```
- `IFS=` preserves leading whitespace
- `-r` prevents backslash interpretation
- The `case` statement skips lines starting with `#` (comments) and empty lines

**5. Pattern matching with case**
```bash
case "$NORMALIZED_PATH" in
    *"$NORMALIZED_ENTRY")
        # matched — block!
        ;;
esac
```
The `*` prefix makes this a suffix match — "does the path end with this entry?"

**6. Communicating results**
```bash
printf "BLOCKED: ..." >&2    # Message goes to stderr (shown to user)
exit 2                        # Exit code 2 = BLOCK
```
- `>&2` redirects output to stderr — this is how the hook tells Claude Code (or the runner) *why* it blocked
- Exit code `2` means "block this action"
- Exit code `0` means "allow"

**7. Testing manually**
```bash
# Should BLOCK (reading .env is secret):
echo '{"tool_name":"Read","tool_input":{"file_path":".env"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_secrets_guard.sh && echo "ALLOWED" || echo "BLOCKED"

# Should ALLOW (reading main.c is fine):
echo '{"tool_name":"Read","tool_input":{"file_path":"src/main.c"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_secrets_guard.sh && echo "ALLOWED" || echo "BLOCKED"
```

**This is the pattern you will repeat for all 6 hooks:** read stdin, extract fields, apply logic, exit with the right code.

---

## 5. The 6 Hooks — Detailed Specifications

**Important note about validation order:** For hooks that check multiple conditions (like the Commit Validator), test the conditions in the order they are listed below. The test inputs are guaranteed to violate **at most one** condition each, and they follow this order — so your output won't conflict with expected results as long as you check in the specified order.

---

### Hook 1: Command Firewall — `pre_command_firewall.sh`

**Type:** PreToolUse | **Trigger:** `Bash`

**Purpose:** Block dangerous shell commands before Claude executes them — the first line of defense.

**Bash skills practiced:** Reading stdin, grep regex matching, reading a config file line by line, exit codes.

**Input JSON:**
```json
{"tool_name":"Bash","tool_input":{"command":"rm -rf /home/user"},"session_id":"s1"}
```

**Behavior:**
1. Resolve paths with the `HOOK_DIR` pattern.
2. Read JSON from stdin. Extract `tool_name` and `command`.
3. If `tool_name` is not `Bash`, exit `0` — this hook only inspects shell commands.
4. Load patterns from `.claude/hooks/config/dangerous_patterns.txt`. Each non-comment, non-empty line is a regex pattern.
5. Test the command against each pattern using `grep -qE`. On the first match:
   - Print an error to `stderr` naming the matched pattern.
   - Exit `2` to block.
6. If no pattern matches, exit `0`.

**Config file** — `.claude/hooks/config/dangerous_patterns.txt` (example — may differ in tests):
```
# One regex per line
rm -rf
rm -r /
git reset --hard
git push.*--force
chmod -R 777
```

**Exit codes:** `0` = allow, `2` = blocked.

**Test examples:**
```bash
# Should pass (exit 0):
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_command_firewall.sh && echo "ALLOWED" || echo "BLOCKED"

# Should block (exit 2):
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/project"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_command_firewall.sh && echo "ALLOWED" || echo "BLOCKED"

# Non-Bash tool — always passes:
echo '{"tool_name":"Edit","tool_input":{"file_path":"main.c"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_command_firewall.sh && echo "ALLOWED" || echo "BLOCKED"
```

---

### Hook 2: Rate Limiter — `pre_rate_limiter.sh`

**Type:** PreToolUse | **Trigger:** `Bash`

**Purpose:** Track how many commands Claude has run per session and block further commands once the limit is reached. Prevents runaway automation.

**Bash skills practiced:** File-based state persistence, parsing structured text, arithmetic with `$(( ))`, per-session tracking.

**Input JSON:**
```json
{"tool_name":"Bash","tool_input":{"command":"git status"},"session_id":"abc123"}
```

**Behavior:**
1. Resolve paths. Extract `session_id` and `command`. If `session_id` is absent, use `"default"`.
2. Read limits from `.claude/hooks/config/hooks.conf`:
   - `MAX_COMMANDS=50` — hard block threshold
   - `WARNING_THRESHOLD=40` — soft warning threshold
3. State is stored in `.claude/hooks/data/.command_count`. Each line has the format:
   ```
   session_id|total_count|cmd_type1:N,cmd_type2:N,...
   ```
   Example: `abc123|15|git:8,ls:4,npm:3`
4. Find the line for the current `session_id` (or start at 0 if not found).
5. Increment total count by 1.
6. Extract the first word of the command (e.g., `git` from `git commit -m ...`) as the command type. Increment its per-type count.
7. Write the updated line back to the state file, replacing the old one for this session.
8. **Reset mechanism:** If `.claude/hooks/data/.reset_commands` exists, delete this session's line from the state file, remove the reset file, then proceed normally (count starts fresh at 1).
9. **Enforce limits:**
   - Total > `MAX_COMMANDS` → exit `2` with count and breakdown on stderr
   - Total > `WARNING_THRESHOLD` → print warning to stderr, exit `0` (allow with warning)
   - Otherwise → exit `0` silently

**Config file** — `.claude/hooks/config/hooks.conf` (example — may differ in tests):
```
MAX_COMMANDS=50
WARNING_THRESHOLD=40
MAX_BACKUPS=5
```

**Exit codes:** `0` = allow (possibly with warning), `2` = limit exceeded.

**Test examples:**
```bash
# First command — should pass:
echo '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"test-s1"}' \
    | bash .claude/hooks/pre_rate_limiter.sh && echo "ALLOWED" || echo "BLOCKED"

# Check the state file:
cat .claude/hooks/data/.command_count

# To test blocking: temporarily set MAX_COMMANDS=2 in hooks.conf,
# run 3 commands with the same session_id, then restore the original value.
```

---

### Hook 3: Commit Message Validator — `pre_commit_validator.sh`

**Type:** PreToolUse | **Trigger:** `Bash`

**Purpose:** Enforce Conventional Commits format. If the prefix is missing, suggest one based on which files were changed.

**Bash skills practiced:** String parsing, regex validation with `[[ =~ ]]`, calling external commands (`git diff`), heuristic logic.

**Input JSON:**
```json
{"tool_name":"Bash","tool_input":{"command":"git commit -m 'add login page'"},"session_id":"s1"}
```

**Behavior (check in this order):**
1. Extract `command`. If it does not contain `git commit`, exit `0`.
2. If the command has no `-m` flag, exit `0` (interactive editor — can't validate).
3. Extract the commit message from `-m "..."`. Handle: `-m "msg"`, `-am "msg"`, `-a -m "msg"`.
4. Load valid prefixes from `.claude/hooks/config/commit_prefixes.txt` (one per line). Build a regex like `^(feat|fix|docs|...): `.
5. **Check 1 — Prefix present?** If prefix is missing:
   - Run `git diff --cached --stat` and `git diff --cached --name-status` to inspect staged changes.
   - Suggest a prefix using heuristics:
     - Files contain `test` or `spec` → suggest `test`
     - Files contain `README` or `.md` → suggest `docs`
     - New files added (status `A` in name-status) → suggest `feat`
     - More deletions than insertions → suggest `refactor`
     - Default → suggest `feat`
   - Exit `2` with: `BLOCKED: Missing prefix. Based on your changes, try: '<prefix>: your message'. Valid prefixes: feat, fix, docs, refactor, test, chore`
6. **Check 2 — Length valid?** Message length must be 10–72 characters → exit `2` if violated.
7. **Check 3 — No trailing period?** Message must not end with a period → exit `2` if it does.
8. All checks pass → exit `0`.

**Config file** — `.claude/hooks/config/commit_prefixes.txt`:
The file will contain a subset of the following valid prefixes — it may include some or all of them, but never a prefix not on this list:
```
feat
fix
docs
refactor
test
chore
```

**Exit codes:** `0` = allow, `2` = invalid message.

**Test examples:**
```bash
# Valid — should pass:
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m '\''feat: add user login page'\''"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_commit_validator.sh && echo "ALLOWED" || echo "BLOCKED"

# Missing prefix — should block with suggestion:
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m '\''added some stuff'\''"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_commit_validator.sh && echo "ALLOWED" || echo "BLOCKED"

# Too short — should block:
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m '\''fix: bug'\''"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_commit_validator.sh && echo "ALLOWED" || echo "BLOCKED"

# Ends with period — should block:
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m '\''feat: add login page.'\''"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_commit_validator.sh && echo "ALLOWED" || echo "BLOCKED"

# Non-commit command — should pass:
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"s1"}' \
    | bash .claude/hooks/pre_commit_validator.sh && echo "ALLOWED" || echo "BLOCKED"
```

---

### Hook 4: Auto-Backup — `post_auto_backup.sh`

**Type:** PostToolUse | **Trigger:** `Edit`

**Purpose:** Every time Claude edits a file, save a timestamped backup. Automatically delete old backups beyond the configured maximum. A safety net for accidental changes.

**Bash skills practiced:** File operations, timestamp formatting, backup rotation with `ls -t` and `tail`, logging.

**Input JSON:**
```json
{"tool_name":"Edit","tool_input":{"file_path":"src/main.c"},"session_id":"abc123"}
```

**Behavior:**
1. Extract `file_path` and `session_id` (default `"default"` if absent).
2. If `file_path` is empty or the file does not exist, exit `0`.
3. Generate a timestamp: `date +%Y-%m-%d_%H%M%S`.
4. Create `.claude/hooks/data/.backups/` if it doesn't exist.
5. Copy the file to `.claude/hooks/data/.backups/<basename>.<timestamp>`.
   Example: `src/main.c` → `.claude/hooks/data/.backups/main.c.2026-04-03_142305`
6. Get file size with `wc -c`.
7. Append to `.claude/hooks/data/session_<session_id>.log`:
   ```
   [2026-04-03 14:23:05] BACKUP src/main.c -> .backups/main.c.2026-04-03_142305 (512 bytes)
   ```
8. **Rotation:** Read `MAX_BACKUPS` from `hooks.conf` (default `5`). Count existing backups for this filename. If count exceeds `MAX_BACKUPS`, list them sorted newest-first (`ls -t`) and delete the oldest ones.
9. Always exit `0`.

**Config value** in `.claude/hooks/config/hooks.conf`: `MAX_BACKUPS=5` (may differ in tests)

**Exit codes:** Always `0`.

**Test examples:**
```bash
# Create a test file and back it up:
echo 'int main() { return 0; }' > /tmp/test_backup.c
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test_backup.c"},"session_id":"s1"}' \
    | bash .claude/hooks/post_auto_backup.sh

# Verify backup was created:
ls .claude/hooks/data/.backups/

# Verify log entry:
cat .claude/hooks/data/session_s1.log
```

---

### Hook 5: Syntax Checker — `post_syntax_checker.sh`

**Type:** PostToolUse | **Trigger:** `Edit`

**Purpose:** After Claude edits a file, run a syntax check appropriate for that file type. Catch errors immediately.

**Bash skills practiced:** `case` statements, file extension extraction, running external commands, capturing output and exit codes.

**Input JSON:**
```json
{"tool_name":"Edit","tool_input":{"file_path":"src/main.c"},"session_id":"abc123"}
```

**Behavior:**
1. Extract `file_path` and `session_id`.
2. If `file_path` is empty or the file doesn't exist, exit `0`.
3. Extract the file extension: `EXTENSION="${FILE_PATH##*.}"`.
4. Use a `case` statement to dispatch:
   - `sh` or `bash` → run `bash -n "$FILE_PATH"`
   - `py` → run `python3 -m py_compile "$FILE_PATH"`
   - `c` or `h` → run `gcc -fsyntax-only "$FILE_PATH"`
   - anything else → print `No syntax checker for .<ext>` to stderr, exit `0`
5. **If check fails (non-zero exit):**
   - Print `SYNTAX ERROR in <file_path>:` + error output to stderr
   - Log: `[YYYY-MM-DD HH:MM:SS] SYNTAX_ERROR <file_path> (<extension>)`
   - Exit `1` (warning — non-fatal)
6. **If check passes:**
   - Print `Syntax OK: <file_path>` to stdout
   - Log: `[YYYY-MM-DD HH:MM:SS] SYNTAX_OK <file_path> (<extension>)`
   - Exit `0`

**Exit codes:** `0` = syntax OK, `1` = syntax error (warning).

**Test examples:**
```bash
# Valid shell script — should print "Syntax OK":
printf '#!/bin/bash\necho hello\n' > /tmp/valid.sh
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/valid.sh"},"session_id":"s1"}' \
    | bash .claude/hooks/post_syntax_checker.sh

# Invalid shell script — should print "SYNTAX ERROR" and exit 1:
printf '#!/bin/bash\nif [ -z ""\n  echo unclosed\n' > /tmp/broken.sh
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/broken.sh"},"session_id":"s1"}' \
    | bash .claude/hooks/post_syntax_checker.sh
echo "Exit code: $?"

# Unknown extension — should exit 0:
echo 'hello' > /tmp/file.xyz
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/file.xyz"},"session_id":"s1"}' \
    | bash .claude/hooks/post_syntax_checker.sh
```

---

### Hook 6: Session Summary — `post_session_summary.sh`

**Type:** Stop | **Trigger:** `*` (runs when Claude session ends)

**Purpose:** Generate a formatted summary report from the session log: backup count, most-edited files, syntax error count.

**Bash skills practiced:** Log parsing with `awk`, `sort | uniq -c`, formatted output with `printf`, infinite-loop guard.

**Input JSON:**
```json
{"session_id":"abc123","cwd":"/home/user/project","stop_hook_active":false}
```

**Behavior:**
1. **Infinite-loop guard (critical!):** Extract `stop_hook_active`. If `true`, exit `0` immediately. This prevents Claude Code from entering an infinite Stop→Hook→Stop loop.
2. Extract `session_id`. Set log path to `.claude/hooks/data/session_<session_id>.log`.
3. If the log doesn't exist or is empty, print `No session activity recorded.` and exit `0`.
4. **Gather statistics from the log:**
   - Total lines = total actions
   - Count `BACKUP` lines → backups made
   - Count `SYNTAX_OK` and `SYNTAX_ERROR` lines separately
   - First and last timestamps → session time range
   - Top 3 most-edited files (from BACKUP lines)
   - File type counts
5. **Generate formatted report to stdout:**

   The report is printed as a Claude Code `systemMessage` (JSON on stdout).
   The sample log `.claude/hooks/data/session_test-session-1.log` contains:
   ```
   [2026-04-07 01:45:09] BACKUP src/main.c -> .backups/main.c.20240101_120000 (512 bytes)
   [2026-04-07 01:45:09] SYNTAX_OK src/main.c (c)
   [2026-04-07 01:45:09] BACKUP src/main.c -> .backups/main.c.20240101_120001 (520 bytes)
   [2026-04-07 01:45:09] BACKUP src/utils.h -> .backups/utils.h.20240101_120002 (128 bytes)
   [2026-04-07 01:45:09] SYNTAX_ERROR src/broken.c (c)
   [2026-04-07 01:45:09] SYNTAX_OK src/utils.h (c)
   ```

   Running:
   ```bash
   echo '{"session_id":"test-session-1","stop_hook_active":false}' \
       | bash .claude/hooks/post_session_summary.sh
   ```

   Produces this stdout (JSON wrapping the report so Claude Code renders it):
   ```json
   {"systemMessage": "<report content — see below>"}
   ```

   The inner report content, rendered from the log above:
   ```
   ╔══════════════════════════════════════╗
   ║        SESSION SUMMARY REPORT        ║
   ╚══════════════════════════════════════╝

   Session: test-session-1
   Period:  2026-04-07 01:45:09 -> 2026-04-07 01:45:09

   ── Activity ─────────────────────────
     Total actions: 6
     Backups made: 3
     Syntax checks: 3
     Syntax errors: 1

   ── Most Edited Files ────────────────
     1. src/main.c (2 edits)
     2. src/utils.h (1 edit)

   ── File Types ───────────────────────
     .c files: 4
     .h files: 2
   ```

   Where each value comes from in the log:

   | Report field | Value | Source in the log |
   |---|---|---|
   | Total actions | 6 | Every line is one action — the log has 6 lines |
   | Backups made | 3 | 3 lines start with `BACKUP` (lines 1, 3, 4) |
   | Syntax checks | 3 | 2 lines are `SYNTAX_OK` + 1 line is `SYNTAX_ERROR` |
   | Syntax errors | 1 | 1 line is `SYNTAX_ERROR` (line 5) |
   | `src/main.c` — 2 edits | most-edited | `src/main.c` is the backed-up file in lines 1 and 3 |
   | `src/utils.h` — 1 edit | second | `src/utils.h` is the backed-up file in line 4 only |
   | `.c` files: 4 | — | `main.c` is referenced in lines 1, 2, 3 and `broken.c` in line 5 |
   | `.h` files: 2 | — | `utils.h` is referenced in lines 4 and 6 |

6. Always exit `0`.

**Exit codes:** Always `0`.

**Test examples:**
```bash
# Empty log — should print "No session activity recorded.":
echo '{"session_id":"empty-session","stop_hook_active":false}' \
    | bash .claude/hooks/post_session_summary.sh

# Loop guard — should exit 0 with no output at all:
echo '{"session_id":"s1","stop_hook_active":true}' \
    | bash .claude/hooks/post_session_summary.sh

# With the provided sample log (session_test-session-1.log):
echo '{"session_id":"test-session-1","stop_hook_active":false}' \
    | bash .claude/hooks/post_session_summary.sh
# Expected stdout: {"systemMessage": "..."} containing the report above
```

---

## 6. Suggested Workflow

Follow this order — each step builds on the previous one.

1. **Read all instructions first** — you're already doing this. Don't start coding until you finish reading.
2. **Study the demo hook** — open `.claude/hooks/pre_secrets_guard.sh` and work through the walkthrough in Section 4. Make sure you understand every line.
3. **Implement `pre_command_firewall.sh`** — this follows the same pattern as the demo. Test it:
   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"s1"}' \
       | bash .claude/hooks/pre_command_firewall.sh && echo "ALLOWED" || echo "BLOCKED"
   ```
4. **Implement `pre_rate_limiter.sh`** — test it, check the state file after each run.
5. **Implement `pre_commit_validator.sh`** — test with valid and invalid commit messages.
6. **Implement `post_auto_backup.sh`** — create a temp file, run the hook, verify backups appear.
7. **Implement `post_syntax_checker.sh`** — test with valid and invalid `.sh` and `.c` files.
8. **Implement `post_session_summary.sh`** — use the sample log to verify the report format.
9. **Implement `hook_runner.sh`** — now that all hooks work individually, wire them together.
10. **Push to GitHub** and verify all automated tests pass. 

**Note:** The automated tests in the repository are a basic sanity check — they do not cover all cases. The final grading will use a more comprehensive test suite with additional edge cases, alongside the oral examination. Passing the provided tests is necessary but not sufficient — make sure your code handles all scenarios described in the specifications, not just the provided test cases.

11. **Test edge cases** — empty input, missing config files, unknown file extensions, absent `session_id`.

---

## 7. About AI Usage

You are allowed to use AI tools to assist with this exercise. **However — you are fully responsible for every line of code you submit.** Some students will be called to an **oral examination** where you will be asked to explain your code and demonstrate that you understand how it works. If you cannot explain your own submission, it will be treated accordingly.

This is a serious warning: use AI as a learning tool, not as a replacement for understanding. Be careful and responsible. We trust you!

That said — this exercise is a genuinely great opportunity to learn Bash at a practical level. The hooks are a real framework, the problems are real, and you can actually use what you build. Put in the work and you'll come out of this with skills you'll use for years.

---

## 8. Beyond the Exercise — Your Hooks in the Real World

If you have access to Claude Code, you can see your hooks run live on a real AI assistant.

**Setup:**
1. Copy the `.claude/` folder into any project directory.
2. The `.claude/settings.json` is already configured to wire all hooks. It looks like this:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             { "type": "command", "command": ".claude/hooks/pre_secrets_guard.sh" },
             { "type": "command", "command": ".claude/hooks/pre_command_firewall.sh" },
             { "type": "command", "command": ".claude/hooks/pre_rate_limiter.sh" },
             { "type": "command", "command": ".claude/hooks/pre_commit_validator.sh" }
           ]
         }
       ],
       "PostToolUse": [
         {
           "matcher": "Edit|Write|MultiEdit",
           "hooks": [
             { "type": "command", "command": ".claude/hooks/post_auto_backup.sh" },
             { "type": "command", "command": ".claude/hooks/post_syntax_checker.sh" }
           ]
         }
       ],
       "Stop": [
         {
           "hooks": [
             { "type": "command", "command": ".claude/hooks/post_session_summary.sh" }
           ]
         }
       ]
     }
   }
   ```
3. Open Claude Code in that directory.
4. Verify hooks are loaded: type `/hooks` inside Claude Code.
5. Test it: ask Claude to "delete all files in /tmp using `rm -rf` command" — your firewall hook should block the `rm -rf` command.
6. When you end the session, the summary hook will print a report of everything that happened.

This is **not required** for the exercise — it's a bonus for those who want to see their work in action in a real AI coding environment.

---

*Good luck and have fun!*
