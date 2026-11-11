# wt config for the Implentio stack repo (bare repo at ~/Implentio/stack).
# Sourced by ~/dotfiles/bin/wt — plain bash; see the defaults at the top of wt.

# every worktree is a window in one shared session
WT_TMUX_MODE=window
WT_SESSION=implentio-worktrees

# typed into an interactive shell, so this is the zshrc alias
# (claude --dangerously-skip-permissions)
WT_AGENT_CMD=cc

# pnpm i is deferred: run it only when starting local servers (dev-up)
WT_SEED_DIRENV=1
WT_SYMLINKS=(
  .kube/config.user.yaml
  .kube/config
  packages/implentio-app/packages/toolbelt/public/config/env.js
  packages/implentio-app/packages/api-v2/.env
  packages/implentio-app/packages/ui/.env
  packages/implentio-app/packages/app-v3/.env
  packages/ai-api/.env
  packages/reconciliation/projects/api/build/resources/main/application-local.yml
)
