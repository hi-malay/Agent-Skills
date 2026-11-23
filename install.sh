#!/usr/bin/env bash
# Restores Claude Code skills/commands/CLAUDE.md + AGENTS.md + superpowers into $HOME
set -e
cd "$(dirname "$0")"
mkdir -p ~/.claude ~/.agents/skills
cp -R claude/. ~/.claude/
cp AGENTS.md ~/AGENTS.md
[ -d ~/.codex/superpowers ] || git clone -q https://github.com/obra/superpowers.git ~/.codex/superpowers
ln -sfn ~/.codex/superpowers/skills ~/.agents/skills/superpowers
echo "Done. Restart Claude Code."
