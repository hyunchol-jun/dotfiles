local M = {}

-- Default configuration
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
  create_split_pane = false,
  -- Split direction: 'h' for horizontal (right), 'v' for vertical (below)
  split_direction = 'h',
  -- Size of the split pane (percentage)
  split_size = 30,
  -- Project-specific configurations
  projects = {
    ['implentio-app'] = {
      auto_open_nvim = true,
      nvim_command = 'nvim',
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
        [1] = 'claude',  -- top-right pane
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
  },
}

-- Helper functions
local function get_project_name(path)
  -- Extract project name from path
  -- Look for .git directory and get the parent folder name
  local git_dir = path:match('(.+)%.git')
  if git_dir then
    return git_dir:match('([^/]+)$')
  end
  -- Fallback: get the top-level directory name
  return path:match('([^/]+)[^/]*$')
end

local function get_project_config(path, base_config)
  local project_name = get_project_name(path)
  local project_config = base_config.projects[project_name] or {}
  
  -- Merge project config with base config
  local config = vim.tbl_deep_extend('force', base_config, project_config)
  
  return config
end

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

local function create_custom_layout(session_name, path, layout)
  if not layout or #layout == 0 then
    return
  end
  
  for _, split in ipairs(layout) do
    local target = split.target_pane and string.format('%s:0.%d', session_name, split.target_pane) or string.format('%s:0', session_name)
    local split_cmd = string.format('tmux split-window -t %s -%s -l %d%% -c %s',
      target,
      split.direction,
      split.size,
      vim.fn.shellescape(path))
    
    local success, result = tmux_command(split_cmd)
    if not success then
      vim.notify('Failed to create split: ' .. result, vim.log.levels.WARN)
      break  -- Stop creating more splits if one fails
    end
  end
  
  -- Select the first pane (where nvim will be)
  tmux_command(string.format('tmux select-pane -t %s:0.0', session_name))
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
    
    -- Create custom layout if specified, otherwise create simple split
    if config.custom_layout then
      create_custom_layout(session_name, path, config.custom_layout)
    elseif config.create_split_pane then
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
    
    -- Execute pane-specific commands if configured
    if config.pane_commands then
      for pane_num, commands in pairs(config.pane_commands) do
        if type(commands) == 'string' then
          -- Single command
          tmux_command(string.format('tmux send-keys -t %s:0.%d "%s" C-m',
            session_name,
            pane_num,
            commands))
        elseif type(commands) == 'table' then
          -- Multiple commands - execute in sequence
          for _, command in ipairs(commands) do
            tmux_command(string.format('tmux send-keys -t %s:0.%d "%s" C-m',
              session_name,
              pane_num,
              command))
          end
        end
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
      -- Get project-specific configuration
      local project_config = get_project_config(metadata.path, M.config)
      local session_name = get_session_name(metadata, project_config)
      vim.notify('Git Worktree: ' .. op .. ' -> tmux session: ' .. session_name)
      handle_tmux_session(session_name, metadata.path, project_config)
    elseif op == Worktree.Operations.Delete then
      local project_config = get_project_config(metadata.path, M.config)
      if project_config.auto_kill_session then
        local session_name = get_session_name(metadata, project_config)
        if tmux_session_exists(session_name) then
          vim.notify('Killing tmux session: ' .. session_name)
          local success, result = tmux_command(string.format('tmux kill-session -t %s', session_name))
          if not success then
            vim.notify('Failed to kill session: ' .. result, vim.log.levels.ERROR)
          end
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
