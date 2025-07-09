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

local function get_session_name(branch, path, config)
  local name
  if config.use_branch_name and branch then
    name = branch
  else
    name = path:match '([^/]+)$'
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

-- Git worktree functions
local function get_git_root()
  local success, output = tmux_command('git rev-parse --show-toplevel 2>/dev/null')
  return success and output or nil
end

local function get_current_branch()
  local success, output = tmux_command('git branch --show-current 2>/dev/null')
  return success and output or nil
end

local function list_worktrees()
  local success, output = tmux_command('git worktree list --porcelain')
  if not success then
    return {}
  end
  
  local worktrees = {}
  local current_worktree = {}
  
  for line in output:gmatch('[^\n]+') do
    if line:match('^worktree ') then
      if current_worktree.path then
        table.insert(worktrees, current_worktree)
      end
      current_worktree = { path = line:match('^worktree (.+)') }
    elseif line:match('^branch ') then
      current_worktree.branch = line:match('^branch refs/heads/(.+)')
    elseif line:match('^detached') then
      current_worktree.branch = 'detached'
    end
  end
  
  if current_worktree.path then
    table.insert(worktrees, current_worktree)
  end
  
  return worktrees
end

-- Public functions
function M.create_worktree()
  vim.ui.input({ prompt = 'Branch name: ' }, function(branch_name)
    if not branch_name or branch_name == '' then
      return
    end
    
    local git_root = get_git_root()
    if not git_root then
      vim.notify('Not in a git repository', vim.log.levels.ERROR)
      return
    end
    
    -- Default path is ../branch_name relative to main worktree
    local parent_dir = vim.fn.fnamemodify(git_root, ':h')
    local worktree_path = parent_dir .. '/' .. branch_name
    
    vim.ui.input({ 
      prompt = 'Worktree path: ', 
      default = worktree_path 
    }, function(path)
      if not path or path == '' then
        return
      end
      
      -- Check if branch exists
      local branch_exists_cmd = string.format('git show-ref --verify --quiet refs/heads/%s', branch_name)
      local branch_exists = tmux_command(branch_exists_cmd)
      
      local create_cmd
      if branch_exists then
        -- Branch exists, just create worktree
        create_cmd = string.format('git worktree add %s %s', 
          vim.fn.shellescape(path), 
          vim.fn.shellescape(branch_name))
      else
        -- Branch doesn't exist, create new branch with worktree
        create_cmd = string.format('git worktree add -b %s %s', 
          vim.fn.shellescape(branch_name),
          vim.fn.shellescape(path))
      end
      
      local success, result = tmux_command(create_cmd)
      if not success then
        vim.notify('Failed to create worktree: ' .. result, vim.log.levels.ERROR)
        return
      end
      
      vim.notify('Created worktree: ' .. branch_name .. ' at ' .. path)
      
      -- Handle tmux session
      local config = get_project_config(path, M.config)
      local session_name = get_session_name(branch_name, path, config)
      handle_tmux_session(session_name, path, config)
    end)
  end)
end

function M.switch_worktree()
  local worktrees = list_worktrees()
  if #worktrees == 0 then
    vim.notify('No worktrees found', vim.log.levels.WARN)
    return
  end
  
  local items = {}
  for _, wt in ipairs(worktrees) do
    table.insert(items, {
      text = string.format('%s (%s)', wt.branch or 'detached', wt.path),
      branch = wt.branch,
      path = wt.path
    })
  end
  
  vim.ui.select(items, {
    prompt = 'Select worktree:',
    format_item = function(item)
      return item.text
    end
  }, function(choice)
    if not choice then
      return
    end
    
    -- Handle tmux session
    local config = get_project_config(choice.path, M.config)
    local session_name = get_session_name(choice.branch, choice.path, config)
    handle_tmux_session(session_name, choice.path, config)
  end)
end

function M.delete_worktree()
  local worktrees = list_worktrees()
  if #worktrees == 0 then
    vim.notify('No worktrees found', vim.log.levels.WARN)
    return
  end
  
  -- Filter out main worktree
  local deletable_worktrees = {}
  for _, wt in ipairs(worktrees) do
    if wt.branch then  -- Main worktree has no branch in porcelain output
      table.insert(deletable_worktrees, wt)
    end
  end
  
  if #deletable_worktrees == 0 then
    vim.notify('No deletable worktrees found', vim.log.levels.WARN)
    return
  end
  
  local items = {}
  for _, wt in ipairs(deletable_worktrees) do
    table.insert(items, {
      text = string.format('%s (%s)', wt.branch, wt.path),
      branch = wt.branch,
      path = wt.path
    })
  end
  
  vim.ui.select(items, {
    prompt = 'Select worktree to delete:',
    format_item = function(item)
      return item.text
    end
  }, function(choice)
    if not choice then
      return
    end
    
    vim.ui.select({ 'Yes', 'No' }, {
      prompt = string.format('Delete worktree %s?', choice.branch)
    }, function(confirm)
      if confirm ~= 'Yes' then
        return
      end
      
      -- Delete the worktree
      local delete_cmd = string.format('git worktree remove %s', vim.fn.shellescape(choice.path))
      local success, result = tmux_command(delete_cmd)
      if not success then
        vim.notify('Failed to delete worktree: ' .. result, vim.log.levels.ERROR)
        return
      end
      
      vim.notify('Deleted worktree: ' .. choice.branch)
      
      -- Kill tmux session if configured
      local config = get_project_config(choice.path, M.config)
      if config.auto_kill_session then
        local session_name = get_session_name(choice.branch, choice.path, config)
        if tmux_session_exists(session_name) then
          vim.notify('Killing tmux session: ' .. session_name)
          local kill_success, kill_result = tmux_command(string.format('tmux kill-session -t %s', session_name))
          if not kill_success then
            vim.notify('Failed to kill session: ' .. kill_result, vim.log.levels.ERROR)
          end
        end
      end
    end)
  end)
end

-- Setup function
function M.setup(user_config)
  -- Merge user config with defaults
  M.config = vim.tbl_extend('force', M.config, user_config or {})
  
  -- Create user commands
  vim.api.nvim_create_user_command('WorktreeCreate', M.create_worktree, {})
  vim.api.nvim_create_user_command('WorktreeSwitch', M.switch_worktree, {})
  vim.api.nvim_create_user_command('WorktreeDelete', M.delete_worktree, {})
end

return M