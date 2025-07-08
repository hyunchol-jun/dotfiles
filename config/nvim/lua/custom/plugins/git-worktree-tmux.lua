local M = {}

-- Configuration
M.config = {
  -- Use branch name instead of directory name for session
  use_branch_name = true,
  -- Prefix for all worktree sessions
  session_prefix = 'wt-',
  -- Auto-kill session on worktree delete
  auto_kill_session = true,
  -- Open new window in session if it already exists
  open_new_window = false,
  -- Auto-approve direnv when creating new sessions
  auto_direnv_allow = true,
  -- Command to run when creating new session
  auto_open_nvim = true,
  -- Custom command to run instead of nvim
  nvim_command = 'nvim',
  -- Create a split pane when creating new session
  create_split_pane = true,
  -- Split direction: 'h' for horizontal (right), 'v' for vertical (below)
  split_direction = 'h',
  -- Size of the split pane (percentage)
  split_size = 50,
}

-- Helper functions
local function get_session_name(metadata, config)
  local name
  if config.use_branch_name and metadata.branch then
    name = metadata.branch
  else
    name = metadata.path:match '([^/]+)$'
  end
  -- Clean up the name for tmux
  name = name:gsub('[%.%:%/]', '_')
  return config.session_prefix .. name
end

local function tmux_command(cmd)
  local output = vim.fn.system(cmd)
  local success = vim.v.shell_error == 0
  return success, vim.trim(output)
end

local function tmux_session_exists(session_name)
  local success = tmux_command('tmux has-session -t ' .. session_name .. ' 2>/dev/null')
  return success
end

local function handle_tmux_session(session_name, path, config)
  if not vim.env.TMUX then
    vim.notify 'Not in tmux, skipping session management'
    return
  end

  if tmux_session_exists(session_name) then
    if config.open_new_window then
      local success, result = tmux_command(string.format('tmux new-window -t %s -c %s', session_name, vim.fn.shellescape(path)))
      if not success then
        vim.notify('Failed to create new window: ' .. result, vim.log.levels.ERROR)
        return
      end
    end
    -- Use vim.cmd for switching sessions to affect the current tmux client
    vim.cmd(string.format('silent !tmux switch-client -t %s', session_name))
    vim.cmd 'redraw!'
  else
    -- First check if direnv needs to be handled
    local envrc_path = path .. '/.envrc'
    local has_envrc = vim.fn.filereadable(envrc_path) == 1
    
    -- Create the session with appropriate initial command
    local create_cmd
    if has_envrc and config.auto_direnv_allow then
      -- Create session that immediately runs direnv allow
      create_cmd = string.format(
        'tmux new-session -d -s %s -c %s "direnv allow && exec $SHELL"',
        session_name,
        vim.fn.shellescape(path)
      )
    else
      -- Create normal session
      create_cmd = string.format('tmux new-session -d -s %s -c %s', 
        session_name, 
        vim.fn.shellescape(path))
    end
    
    local success, result = tmux_command(create_cmd)
    if not success then
      vim.notify('Failed to create session: ' .. result, vim.log.levels.ERROR)
      return
    end
    
    -- Wait a bit for the shell to initialize properly
    vim.cmd('sleep 300m')
    
    -- Create split pane if configured
    if config.create_split_pane then
      local split_cmd = string.format('tmux split-window -t %s:0 -%s -l %d%% -c %s',
        session_name,
        config.split_direction,
        config.split_size,
        vim.fn.shellescape(path))
      
      local split_success, split_result = tmux_command(split_cmd)
      if not split_success then
        vim.notify('Failed to create split pane: ' .. split_result, vim.log.levels.WARN)
      else
        -- Select the first pane (left/top)
        tmux_command(string.format('tmux select-pane -t %s:0.0', session_name))
      end
    end
    
    -- Start nvim in the first pane if configured
    if config.auto_open_nvim then
      -- Clear the line first in case there's any residual text
      tmux_command(string.format('tmux send-keys -t %s:0.0 C-c C-u', session_name))
      
      -- Send nvim command
      tmux_command(string.format('tmux send-keys -t %s:0.0 "%s" C-m',
        session_name,
        config.nvim_command))
    end
    
    -- Switch to new session
    vim.cmd(string.format('silent !tmux switch-client -t %s', session_name))
    vim.cmd 'redraw!'
  end
end

-- Setup function
M.setup = function(user_config)
  -- Merge user config with defaults
  M.config = vim.tbl_extend('force', M.config, user_config or {})

  -- Require git-worktree here, after the plugin is loaded
  local Worktree = require 'git-worktree'

  -- Register the hook
  Worktree.on_tree_change(function(op, metadata)
    if op == Worktree.Operations.Create or op == Worktree.Operations.Switch then
      local session_name = get_session_name(metadata, M.config)
      vim.notify('Git Worktree: ' .. op .. ' -> tmux session: ' .. session_name)
      handle_tmux_session(session_name, metadata.path, M.config)
    elseif op == Worktree.Operations.Delete and M.config.auto_kill_session then
      local session_name = get_session_name(metadata, M.config)
      if tmux_session_exists(session_name) then
        vim.notify('Killing tmux session: ' .. session_name)
        local success, result = tmux_command(string.format('tmux kill-session -t %s', session_name))
        if not success then
          vim.notify('Failed to kill session: ' .. result, vim.log.levels.ERROR)
        end
      end
    end
  end)
end

return {
  'ThePrimeagen/git-worktree.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require('git-worktree').setup()
    require('telescope').load_extension 'git_worktree'
    -- Setup tmux integration
    M.setup()
  end,
  keys = {
    { '<leader>gws', "<CMD>lua require('telescope').extensions.git_worktree.git_worktrees()<CR>", desc = '[G]it [W]orktree [S]witch' },
    { '<leader>gwc', "<CMD>lua require('telescope').extensions.git_worktree.create_git_worktree()<CR>", desc = '[G]it [W]orktree [C]reate' },
  },
}
