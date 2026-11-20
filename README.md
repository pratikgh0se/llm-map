# llm-map

Label, classify or check each item of a large list with a small model. Claude Code then counts the exact answers with a script.

`llm_map.py` sends your items to `claude -p` in parallel batches (Haiku by default). It writes one JSON line for each item. The main model reads the output file and aggregates it. It does not guess a count from a sample.

This tool came from [lossless-handoff](https://github.com/pratikgh0se/lossless-handoff), where it was an opt-in part (`--llm-map`). It now lives here as its own repository.

## Honest result

I tested it on OOLONG, a benchmark of large aggregation tasks. There were 400 tasks. Arm C (Claude Code with llm_map and its skill) scored 0.731. Plain Claude Code scored 0.711. Plain Claude Code with a hint to use a subagent scored 0.730. This is no measurable gain. The cost was about equal. In the arm C runs, 199 of 206 llm_map calls succeeded.

Use it for the reason below, not because it raises a benchmark score.

## When to use it

Use it when a task needs an exact answer for each of hundreds or thousands of items, and you want the answers in a file. Examples: label the tone of 3,000 reviews, extract a value from each log line, check each row against a rule.

Do not use it in these cases:

- The list has fewer than about 100 items. Ask the main model directly.
- An exact rule works. Use a regex or a script. It is free and faster.
- The items hold secrets. The text goes to the Anthropic API.
- You need the model to reason across items. Each batch is judged alone.

## Install

```
git clone https://github.com/pratikgh0se/llm-map
cd llm-map
./install.sh --dry-run   # show what would change
./install.sh
```

Install paths (the same as in lossless-handoff):

- `~/.claude/hooks/llm_map.py`
- `~/.claude/skills/llm-map/SKILL.md`

The installer does not change `settings.json`. It backs up a file that it replaces, to `~/.claude/hooks/.llm-map-backup-<timestamp>/`. Run `./install.sh --uninstall` to remove both files. You need `python3` and the `claude` command on your PATH.

If you installed llm_map with lossless-handoff before, run `./install.sh` once. The paths are the same, so nothing breaks.

## Usage

```
python3 ~/.claude/hooks/llm_map.py --in reviews.txt --prompt "Label each review as positive, negative or mixed." --out labels.jsonl --labels "positive|negative|mixed"
```

- `--in` is a text file with one item on each line, or a `.jsonl` file with `text` and an optional `id`.
- `--out` gets one JSON line for each item, in input order, with `i`, `text`, `out` and (if it failed) `error`.
- `--labels "a|b|c"` sets the allowed answers (2 or more, split on `|`; not with `--json-out`). `out` is then always one of the labels. A reply maps to a label when it equals a label (trim, case fold), or when it is a prefix of exactly one label (or the other way round) that ends at a word end. Other replies are retried once, then they get `out` null and `error: "label: <reply>"`.
- `--json-out` lets `out` be any JSON value.
- `--model` (default `haiku`), `--batch` (default 100 items), `--jobs` (default 8 batches at the same time), `--max-usd` (default 2.00).
- stderr gets `llm_map: <done> of <n> items done` after each batch. The last stdout line is `llm_map: <n> items, <ok> ok, <failed> failed, <b> batches, cost $<x>`.
- Exit code: 0 when all items have an answer, 3 when some failed, 2 on a usage error.

With the skill installed, Claude Code runs the tool by itself when a task needs an answer for each item of a large list.

## Cost

Each batch is a real model call. Haiku batches of 100 items cost a fraction of a cent each. `--max-usd` stops new batches when the cap would pass. The unsent items get `error: "budget"`. The summary line shows the cost that the calls reported. In the OOLONG test, the total cost with llm_map was about equal to plain Claude Code.

## Limits

- It needs the local `claude` command and a login. It makes real API calls.
- The batch prompt is an argument of the command. There is no size cap. The default batch of 100 short items stays far below the system limit.
- A failed item is not filled with a guess. Check the `failed` count and the `error` fields.
- 3,000 items take about one minute with the defaults. Run it as a foreground Bash call with a timeout of 600000 ms.
- The Claude Code sandbox can block the call to the API. If it does, add `python3 ~/.claude/hooks/llm_map.py *` to the sandbox excluded commands.

See [SECURITY.md](SECURITY.md) for what is sent and where.

## Tests

`bash tests/smoke.sh` runs offline. It uses a fake `claude` command, so it makes no model call.

## License

MIT. See [LICENSE](LICENSE).
