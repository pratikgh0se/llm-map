# Security

## What the installer touches

`install.sh` reads and writes only these paths:

- `~/.claude/hooks/llm_map.py`: the tool.
- `~/.claude/skills/llm-map/SKILL.md`: the skill. Install writes it only when it is missing or holds our marker line (`<!-- lossless-handoff:llm-map-skill -->`). A file without the marker stays unchanged.
- `~/.claude/hooks/.llm-map-backup-<timestamp>/`: a copy of a file that install replaces.

It does not read or write `settings.json`. `./install.sh --uninstall` removes the tool and the marked skill only.

## What the tool sends and where

`llm_map.py` runs the local `claude -p` command, one call for each batch of items. The text of your items and your `--prompt` go to the Anthropic API through that command, with your own Claude Code login. The tool opens no network connection of its own.

- Each call has no tools, no hooks, no MCP servers and no saved session. The working folder is a new temp folder that the tool deletes after the call.
- The batch prompt is an argument of the command. A process list on the same machine can show it.
- Do not send secrets. The tool does not remove secrets from your items.
- The output file holds your item text and the answers. It is written in the folder that you choose, with normal file permissions.
- `LLM_MAP_CLAUDE` replaces the `claude` command. Set it only to a command that you trust.
- Each call costs money. Use `--max-usd` to cap the cost.

## Report a problem

Open a private security advisory on the GitHub repository, or an issue if the problem is not sensitive.
