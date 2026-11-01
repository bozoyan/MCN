---
name: "worktree"
description: "Git worktree 管理规范与操作指南。Invoke when user asks about git worktree, parallel development, or managing multiple branches."
---

# Git Worktree 规范

## Worktree 目录位置

- 所有 worktree 统一放置在 `<project-parent-path>/<project-name>-worktrees/` 目录下。
- 主仓库位于 `<project-parent-path>/<project-name>/`，不作为 worktree 使用。

## Worktree 命名规则

- Worktree 目录命名格式：`{branch-name}` 或 `{feature/branch-name}`，保持与分支名称一致。
- 示例：
  - 分支 `feature/ai-chat` → worktree 路径 `<project-parent-path>/<project-name>-worktrees/feature-ai-chat`
  - 分支 `bugfix/layout-overflow` → worktree 路径 `<project-parent-path>/<project-name>-worktrees/bugfix-layout-overflow`
  - 分支 `develop` → worktree 路径 `<project-parent-path>/<project-name>-worktrees/develop`

## Worktree 使用场景

- **并行开发多个功能**：在不同 worktree 中同时开发不同功能，无需频繁切换分支。
- **紧急修复**：在独立 worktree 中处理紧急 bug，不影响当前开发进度。
- **代码审查**：在独立 worktree 中检出他人分支进行测试和审查。
- **长期维护分支**：为长期存在的分支（如 `develop`、`staging`）创建独立 worktree。

## Worktree 操作命令

### 创建 Worktree

```bash
# 创建新分支并创建 worktree
git worktree add <project-parent-path>/<project-name>-worktrees/feature-xyz -b feature/xyz

# 为已存在的分支创建 worktree
git worktree add <project-parent-path>/<project-name>-worktrees/develop develop

# 基于远程分支创建 worktree
git worktree add <project-parent-path>/<project-name>-worktrees/feature-abc origin/feature/abc
```

### 管理 Worktree

```bash
# 列出所有 worktree
git worktree list

# 在指定 worktree 中执行命令
cd <project-parent-path>/<project-name>-worktrees/feature-xyz
git status

# 删除 worktree（需先确保分支已合并或不再需要）
git worktree remove <project-parent-path>/<project-name>-worktrees/feature-xyz

# 清理已删除分支的 worktree 引用
git worktree prune
```

## Worktree 最佳实践

1. **功能开发完成后及时清理**：分支合并后立即删除对应的 worktree。
2. **命名清晰**：worktree 目录名应能清晰反映对应分支的用途。
3. **独立测试环境**：每个 worktree 可以运行独立的测试实例，避免相互干扰。
4. **文档同步**：在 worktree 中修改文档时，注意主仓库和其他 worktree 的同步。
