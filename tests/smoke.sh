#!/usr/bin/env bash
# Offline smoke tests for llm_map. A fake claude command replaces the model.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.claude"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

FK="$T/fake-claude.py"
cat > "$FK" <<'PY'
import json, os, re, sys
a = sys.argv[1:]
prompt = a[a.index("-p") + 1]
with open(os.environ["FAKE_LOG"], "a") as f:
    f.write(json.dumps({"argv": a, "cwd": os.getcwd()}) + "\n")
drop = os.environ.get("FAKE_DROP")  # item number to drop
once = os.environ.get("FAKE_ONCE")  # "1": drop it on the first call only
seen = os.environ["FAKE_LOG"] + ".seen"
lines = []
for m in re.finditer(r"^(\d+): ", prompt, re.M):
    i = int(m.group(1))
    if drop and i == int(drop) and not (once and os.path.exists(seen)):
        continue
    lines.append(json.dumps({"i": i, "out": "L%d" % i}))
if drop and once:
    open(seen, "w").close()
print(json.dumps({"type": "result", "result": "```json\n" + "\n".join(lines) + "\n```", "total_cost_usd": 0.01}))
PY
export LLM_MAP_CLAUDE="python3 $FK" FAKE_LOG="$T/f60.log"
LM="$ROOT/llm_map.py"
seq 1 100 | sed 's/^/item /' > "$T/f60-in.txt"

# 100 items, --batch 40: 3 batches, order kept, summary line
: > "$FAKE_LOG"
o="$(cd "$T" && python3 "$LM" --in "$T/f60-in.txt" --prompt "label" --out "$T/f60-out.jsonl" --batch 40)" || fail "exit"
grep -q '^llm_map: 100 items, 100 ok, 0 failed, 3 batches, cost \$0.0300$' <<<"$o" || fail "summary: $o"
python3 - "$T/f60-out.jsonl" <<'PY' || fail "out file"
import json, sys
r = [json.loads(l) for l in open(sys.argv[1])]
assert [x["i"] for x in r] == list(range(1, 101)) and all(x["out"] == "L%d" % x["i"] and "error" not in x for x in r), r[:2]
PY
# call flags: no tools, no hooks, no MCP, no session; cwd is gone after the run
python3 - "$FAKE_LOG" "$T" <<'PY' || fail "call flags"
import json, os, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
a = rows[0]["argv"]
assert "-p" in a and a[a.index("--model") + 1] == "haiku" and a[a.index("--output-format") + 1] == "json", a
assert a[a.index("--tools") + 1] == "" and "--strict-mcp-config" in a and "--no-session-persistence" in a, a
assert "disableAllHooks" in a[a.index("--settings") + 1], a
assert not os.path.exists(rows[0]["cwd"]) and rows[0]["cwd"] != sys.argv[2], rows[0]
PY
# item dropped once, then answered on the retry
rm -f "$FAKE_LOG.seen"
FAKE_DROP=7 FAKE_ONCE=1 python3 "$LM" --in "$T/f60-in.txt" --prompt "label" --out "$T/f60-out2.jsonl" >/dev/null || fail "retry exit"
sed -n 7p "$T/f60-out2.jsonl" | grep -q '"out": "L7"' && ! sed -n 7p "$T/f60-out2.jsonl" | grep -q error || fail "item 7"
# item never answered: exit 3
set +e; o="$(FAKE_DROP=7 python3 "$LM" --in "$T/f60-in.txt" --prompt "label" --out "$T/f60-out3.jsonl")"; rc=$?; set -e
[ "$rc" = 3 ] && grep -q ' 1 failed,' <<<"$o" && sed -n 7p "$T/f60-out3.jsonl" | grep -q '"out": null, "error"' || fail "failed item (rc=$rc): $o"
# missing file and empty input: exit 2, no out file
: > "$T/f60-empty.txt"
set +e
python3 "$LM" --in "$T/nope.txt" --prompt x --out "$T/f60-o4.jsonl" 2>"$T/f60.err"; r1=$?
python3 "$LM" --in "$T/f60-empty.txt" --prompt x --out "$T/f60-o5.jsonl" 2>>"$T/f60.err"; r2=$?
set -e
[ "$r1" = 2 ] && [ "$r2" = 2 ] && [ -s "$T/f60.err" ] && [ ! -e "$T/f60-o4.jsonl" ] && [ ! -e "$T/f60-o5.jsonl" ] || fail "usage errors ($r1 $r2)"
ok "batches, retry, failures, usage errors, call flags"

# default batch 100 (3 calls for 250 items) and progress on stderr
seq 1 250 | sed 's/^/item /' > "$T/f61-in.txt"
: > "$FAKE_LOG"
python3 "$LM" --in "$T/f61-in.txt" --prompt "label" --out "$T/f61-out.jsonl" 2>"$T/f61.err" >/dev/null || fail "default batch exit"
[ "$(wc -l < "$FAKE_LOG" | tr -d ' ')" = 3 ] || fail "call count"
python3 - "$FAKE_LOG" <<'PY' || fail "batch sizes"
import json, re, sys
n = sorted(len(re.findall(r"^\d+: ", (lambda a: a[a.index("-p") + 1])(json.loads(l)["argv"]), re.M)) for l in open(sys.argv[1]))
assert n == [50, 100, 100], n
PY
[ "$(grep -c '^llm_map: [0-9]* of 250 items done$' "$T/f61.err")" = 3 ] && tail -n 1 "$T/f61.err" | grep -qx 'llm_map: 250 of 250 items done' || fail "progress: $(cat "$T/f61.err")"
ok "default batch size and progress lines"

# --labels: mapping and one resend
FK2="$T/fake-claude2.py"
cat > "$FK2" <<'PY'
import json, re, sys
a = sys.argv[1:]
prompt = a[a.index("-p") + 1]
rep = ["numeric", "Human Being", "location", "1790"]
lines = [json.dumps({"i": int(m.group(1)), "out": rep[(int(m.group(1)) - 1) % 4]}) for m in re.finditer(r"^(\d+): ", prompt, re.M)]
print(json.dumps({"type": "result", "result": "\n".join(lines), "total_cost_usd": 0.01}))
PY
seq 1 4 | sed 's/^/q /' > "$T/f61-l.txt"
set +e
LLM_MAP_CLAUDE="python3 $FK2" python3 "$LM" --in "$T/f61-l.txt" --prompt "label" --labels "numeric value|human being|location" --out "$T/f61-lo.jsonl" >"$T/f61-l.out" 2>/dev/null; rc=$?
set -e
python3 - "$T/f61-lo.jsonl" <<'PY' || fail "label mapping"
import json, sys
r = [json.loads(l) for l in open(sys.argv[1])]
assert [x["out"] for x in r[:3]] == ["numeric value", "human being", "location"], r
assert r[3]["out"] is None and r[3]["error"].startswith("label:"), r[3]
PY
[ "$rc" = 3 ] && grep -q ' 1 failed, 2 batches,' "$T/f61-l.out" || fail "label rc=$rc $(cat "$T/f61-l.out")"
set +e
python3 "$LM" --in "$T/f61-l.txt" --prompt x --labels "a" --out "$T/f61-u1.jsonl" 2>/dev/null; r1=$?
python3 "$LM" --in "$T/f61-l.txt" --prompt x --labels "a|b" --json-out --out "$T/f61-u2.jsonl" 2>/dev/null; r2=$?
set -e
[ "$r1" = 2 ] && [ "$r2" = 2 ] && [ ! -e "$T/f61-u1.jsonl" ] && [ ! -e "$T/f61-u2.jsonl" ] || fail "label usage errors ($r1 $r2)"
ok "--labels mapping, resend and usage errors"

# install and uninstall in a temp HOME
SK="$HOME/.claude/skills/llm-map/SKILL.md"; LMD="$HOME/.claude/hooks/llm_map.py"
echo '{"keep":1}' > "$HOME/.claude/settings.json"
"$ROOT/install.sh" --dry-run >/dev/null; [ ! -e "$SK" ] && [ ! -e "$LMD" ] || fail "dry-run wrote files"
"$ROOT/install.sh" >/dev/null
grep -qF "<!-- lossless-handoff:llm-map-skill -->" "$SK" && grep -q "^name: llm-map$" "$SK" && grep -q "llm_map.py" "$SK" \
  && [ -x "$LMD" ] && cmp -s "$LMD" "$ROOT/llm_map.py" || fail "install"
[ "$(cat "$HOME/.claude/settings.json")" = '{"keep":1}' ] || fail "settings.json changed"
# an old different copy is backed up and replaced
echo "# old" > "$LMD"
"$ROOT/install.sh" >/dev/null
cmp -s "$LMD" "$ROOT/llm_map.py" && ls "$HOME/.claude/hooks"/.llm-map-backup-*/* >/dev/null 2>&1 || fail "no backup of old copy"
# a skill that is not ours stays
printf 'mine\n' > "$SK"; cp "$SK" "$T/mine"
o="$("$ROOT/install.sh")"
# shellcheck disable=SC2088  # the literal ~ is the expected output text
cmp -s "$SK" "$T/mine" && grep -qF "~/.claude/skills/llm-map/SKILL.md exists and is not ours; left unchanged." <<<"$o" || fail "foreign skill touched"
"$ROOT/install.sh" --uninstall >/dev/null
[ -f "$SK" ] && [ ! -e "$LMD" ] || fail "uninstall: foreign skill removed or tool kept"
rm "$SK"; "$ROOT/install.sh" >/dev/null
"$ROOT/install.sh" --uninstall --dry-run >/dev/null; [ -f "$SK" ] && [ -f "$LMD" ] || fail "uninstall dry-run removed files"
"$ROOT/install.sh" --uninstall >/dev/null
[ ! -e "$SK" ] && [ ! -e "$LMD" ] || fail "uninstall left our files"
ok "install, dry-run, backup, foreign skill kept, uninstall"
echo "all smoke tests passed"
