#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/reveric-agent-rules.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  failures=$((failures + 1))
}

find .agents/rules -maxdepth 1 -type f -name '*.md' -print | sort -u >"$tmp_dir/all_rules"
grep -oE '\.agents/rules/[A-Za-z0-9_.-]+\.md' AGENTS.md | sort -u >"$tmp_dir/indexed_rules" || true
comm -23 "$tmp_dir/all_rules" "$tmp_dir/indexed_rules" >"$tmp_dir/unindexed_rules"

if [[ -s "$tmp_dir/unindexed_rules" ]]; then
  fail "以下顶层 rule 未被 AGENTS.md 路由："
  sed 's/^/      /' "$tmp_dir/unindexed_rules" >&2
else
  pass "全部顶层 rule 均被 AGENTS.md 路由"
fi

grep -oE '\.agents/rules/[A-Za-z0-9_./-]+\.md' AGENTS.md | sort -u >"$tmp_dir/references" || true
missing_reference=0
while IFS= read -r path; do
  if [[ ! -e "$path" ]]; then
    printf '      %s\n' "$path" >&2
    missing_reference=1
  fi
done <"$tmp_dir/references"

if [[ "$missing_reference" -eq 1 ]]; then
  fail "AGENTS.md 包含不存在的 rule 引用"
else
  pass "AGENTS.md 的 rule 引用均存在"
fi

if grep -nE '/Users/|/home/[A-Za-z0-9._-]+/' AGENTS.md .agents/rules/*.md >"$tmp_dir/personal_paths"; then
  fail "Agent 指令包含个人绝对路径："
  sed 's/^/      /' "$tmp_dir/personal_paths" >&2
else
  pass "Agent 指令不包含个人绝对路径"
fi

if grep -rnE 'Icon\(Icons\.' .agents/rules/hooks >"$tmp_dir/material_icon_examples"; then
  fail "Hooks 规则示例包含项目禁止的 Material 图标："
  sed 's/^/      /' "$tmp_dir/material_icon_examples" >&2
else
  pass "Hooks 规则示例不使用 Material 图标"
fi

find . -maxdepth 1 -iname 'claude.md' -print >"$tmp_dir/claude_entries"
if [[ -s "$tmp_dir/claude_entries" ]]; then
  fail "Agent 指令只允许 AGENTS.md，需删除："
  sed 's/^/      /' "$tmp_dir/claude_entries" >&2
else
  pass "Agent 指令只使用 AGENTS.md"
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'Agent rule checks failed: %d\n' "$failures" >&2
  exit 1
fi

printf 'All agent rule checks passed.\n'
