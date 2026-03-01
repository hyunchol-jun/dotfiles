-- Project-specific configurations for worktree-tmux
-- Keys must match the git repository directory name
return {
  ['implentio-app'] = {
    auto_open_nvim = true,
    nvim_command = 'nvim',
    nvim_startup_command = ':!pnpm i',
    -- Custom layout: multiple panes with specific commands
    custom_layout = {
      -- First split: vertical 50/50 (nvim left, terminal area right)
      { direction = 'h', size = 50 },
      -- Second split: in right pane, horizontal split (top/bottom)
      { target_pane = 1, direction = 'v', size = 50 },
      -- Third split: in bottom-right pane, vertical split (left/right)
      { target_pane = 2, direction = 'h', size = 50 },
    },
    -- Commands to run in each pane after layout is created
    pane_commands = {
      [1] = 'claude --model claude-opus-4-1-20250805 --dangerously-skip-permissions',  -- top-right pane
      [2] = {  -- bottom-left pane (api-v2)
        'cd packages/api-v2',
        'cp ~/Implentio/implentio-app.git/main/packages/api-v2/.env .',
      },
      [3] = {  -- bottom-right pane (ui)
        'cd packages/ui',
        'cp ~/Implentio/implentio-app.git/main/packages/ui/.env .',
      },
    },
  },
  ['stack'] = {
    tmux_mode = 'window',
    shared_session_name = 'implentio-worktrees',
    auto_open_nvim = true,
    nvim_command = 'nvim',
    nvim_startup_command = ':!pnpm i',
    custom_layout = {
      { direction = 'h', size = 50 },
    },
    pane_commands = {
      [1] = 'cc',
    },
  },
}
