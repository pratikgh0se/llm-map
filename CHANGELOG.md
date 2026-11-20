# Changelog

## [0.1.0] - 2026-11-20

First release as its own repository. The tool came from [lossless-handoff](https://github.com/pratikgh0se/lossless-handoff), where it was versions 0.12.0 and 0.12.1 (F60 and F61). The code is the same as in lossless-handoff 0.13.0.

- `llm_map.py`: labels each item of a large list with a small model, in parallel batches. It writes one JSON line for each item, retries missing items once and has a cost cap (`--max-usd`).
- `--labels "a|b|c"` limits the answers to a fixed set.
- `skill/SKILL.md`: the skill that tells Claude Code when and how to run the tool.
- `install.sh` with `--dry-run` and `--uninstall`. It uses the same install paths as lossless-handoff and it changes no `settings.json` entry. It makes a backup of a file that it replaces.
- Offline smoke tests (`tests/smoke.sh`) with a fake `claude` command, and CI on ubuntu and macOS.
