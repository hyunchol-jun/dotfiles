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
  -- Vim command to run after nvim starts (e.g., ':!pnpm i')
  nvim_startup_command = nil,
  -- Create a split pane when creating new session
  create_split_pane = false,
  -- Split direction: 'h' for horizontal (right), 'v' for vertical (below)
  split_direction = 'h',
  -- Size of the split pane (percentage)
  split_size = 30,
  -- Merge settings
  default_merge_strategy = 'merge', -- 'merge', 'rebase', or 'squash'
  auto_delete_branch = true,        -- delete branch after successful merge
  merge_target_branch = nil,        -- nil = auto-detect via git symbolic-ref refs/remotes/origin/HEAD
  -- tmux mode: 'session' (default, each worktree gets its own session) or
  --            'window' (all worktrees as windows in a shared session)
  tmux_mode = 'session',
  -- Name of the shared tmux session (required when tmux_mode = 'window')
  shared_session_name = nil,
  -- Kill the shared session when the last window is removed
  auto_kill_empty_session = true,
  -- Project-specific configurations (loaded from worktree-tmux-projects.lua)
  projects = require('custom.worktree-tmux-projects'),
}

-- Helper functions
local function get_project_name(path)
  -- Use git to find the shared git directory (works for bare and non-bare repos)
  local git_common = vim.trim(vim.fn.system(
    string.format('git -C %s rev-parse --git-common-dir 2>/dev/null', vim.fn.shellescape(path))))
  if vim.v.shell_error == 0 and git_common ~= '' then
    -- Resolve to absolute path if relative
    if not git_common:match('^/') then
      local abs = vim.trim(vim.fn.system(
        string.format('realpath %s', vim.fn.shellescape(path .. '/' .. git_common))))
      if abs ~= '' then
        git_common = abs
      end
    end
    -- /path/project.git -> project, /path/project/.git -> project
    local name = git_common:gsub('/%.git$', ''):gsub('%.git$', ''):match('([^/]+)$')
    if name and name ~= '' then
      return name
    end
  end
  -- Fallback: extract from path pattern or directory name
  local git_dir = path:match('(.+)%.git')
  if git_dir then
    return git_dir:match('([^/]+)$')
  end
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
  name = name:gsub('[^%w%-_]', '_')
  return config.session_prefix .. name
end

local function get_window_name(branch, path, config)
  local name
  if config.use_branch_name and branch then
    name = branch
  else
    name = path:match '([^/]+)$'
  end
  return name:gsub('[^%w%-_]', '_')
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

local function tmux_window_exists(session_name, window_name)
  local success = tmux_command(
    string.format("tmux list-windows -t %s -F '#{window_name}' 2>/dev/null | grep -qx %s",
      vim.fn.shellescape(session_name),
      vim.fn.shellescape(window_name)))
  return success
end

-- window_target: e.g. "session:0" or "session:window_name"
local function tmux_send_keys(window_target, pane, text)
  local target = string.format('%s.%d', window_target, pane)
  vim.fn.system({'tmux', 'send-keys', '-t', target, text, 'C-m'})
end

-- window_target: e.g. "session:0" or "session:window_name"
local function create_custom_layout(window_target, path, layout)
  if not layout or #layout == 0 then
    return
  end

  for _, split in ipairs(layout) do
    local target = split.target_pane and string.format('%s.%d', window_target, split.target_pane) or window_target
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
  tmux_command(string.format('tmux select-pane -t %s.0', window_target))
end

-- Apply layout, pane commands, and nvim to a window_target
local function setup_window_layout(window_target, path, config)
  -- Wait a bit for the shell to initialize properly
  vim.cmd('sleep 300m')

  -- Create custom layout if specified, otherwise create simple split
  if config.custom_layout then
    create_custom_layout(window_target, path, config.custom_layout)
  elseif config.create_split_pane then
    local split_cmd = string.format('tmux split-window -t %s -%s -l %d%% -c %s',
      window_target,
      config.split_direction,
      config.split_size,
      vim.fn.shellescape(path))

    local split_success, split_result = tmux_command(split_cmd)
    if not split_success then
      vim.notify('Failed to create split pane: ' .. split_result, vim.log.levels.WARN)
    else
      tmux_command(string.format('tmux select-pane -t %s.0', window_target))
    end
  end

  -- Execute pane-specific commands if configured
  if config.pane_commands then
    for pane_num, commands in pairs(config.pane_commands) do
      if type(commands) == 'string' then
        tmux_send_keys(window_target, pane_num, commands)
      elseif type(commands) == 'table' then
        for _, command in ipairs(commands) do
          tmux_send_keys(window_target, pane_num, command)
        end
      end
    end
  end

  -- Start nvim in the first pane if configured
  if config.auto_open_nvim then
    local target = string.format('%s.0', window_target)
    vim.fn.system({'tmux', 'send-keys', '-t', target, 'C-c', 'C-u'})
    tmux_send_keys(window_target, 0, config.nvim_command)
    if config.nvim_startup_command then
      vim.cmd('sleep 1000m')
      tmux_send_keys(window_target, 0, config.nvim_startup_command)
    end
  end
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

    setup_window_layout(session_name .. ':0', path, config)

    -- Switch to new session
    vim.cmd(string.format('silent !tmux switch-client -t %s', session_name))
    vim.cmd 'redraw!'
  end
end

local function handle_tmux_window(session_name, window_name, path, config)
  if not vim.env.TMUX then
    vim.notify 'Not in tmux, skipping session management'
    return
  end

  if tmux_session_exists(session_name) then
    if tmux_window_exists(session_name, window_name) then
      -- Window already exists, just switch to it
      vim.cmd(string.format('silent !tmux switch-client -t %s:%s',
        session_name, window_name))
      vim.cmd 'redraw!'
    else
      -- Session exists but window doesn't — create the window
      local create_cmd
      local envrc_path = path .. '/.envrc'
      local has_envrc = vim.fn.filereadable(envrc_path) == 1

      if has_envrc and config.auto_direnv_allow then
        create_cmd = string.format(
          'tmux new-window -t %s -n %s -c %s "direnv allow && exec $SHELL"',
          vim.fn.shellescape(session_name),
          vim.fn.shellescape(window_name),
          vim.fn.shellescape(path))
      else
        create_cmd = string.format('tmux new-window -t %s -n %s -c %s',
          vim.fn.shellescape(session_name),
          vim.fn.shellescape(window_name),
          vim.fn.shellescape(path))
      end

      local success, result = tmux_command(create_cmd)
      if not success then
        vim.notify('Failed to create window: ' .. result, vim.log.levels.ERROR)
        return
      end

      local window_target = session_name .. ':' .. window_name
      setup_window_layout(window_target, path, config)

      vim.cmd(string.format('silent !tmux switch-client -t %s:%s',
        session_name, window_name))
      vim.cmd 'redraw!'
    end
  else
    -- Session doesn't exist — create it with the window name
    local create_cmd
    local envrc_path = path .. '/.envrc'
    local has_envrc = vim.fn.filereadable(envrc_path) == 1

    if has_envrc and config.auto_direnv_allow then
      create_cmd = string.format(
        'tmux new-session -d -s %s -n %s -c %s "direnv allow && exec $SHELL"',
        vim.fn.shellescape(session_name),
        vim.fn.shellescape(window_name),
        vim.fn.shellescape(path))
    else
      create_cmd = string.format('tmux new-session -d -s %s -n %s -c %s',
        vim.fn.shellescape(session_name),
        vim.fn.shellescape(window_name),
        vim.fn.shellescape(path))
    end

    local success, result = tmux_command(create_cmd)
    if not success then
      vim.notify('Failed to create session: ' .. result, vim.log.levels.ERROR)
      return
    end

    local window_target = session_name .. ':' .. window_name
    setup_window_layout(window_target, path, config)

    vim.cmd(string.format('silent !tmux switch-client -t %s:%s',
      session_name, window_name))
    vim.cmd 'redraw!'
  end
end

local function dispatch_tmux(branch, path, config)
  if config.tmux_mode == 'window' then
    local session_name = config.shared_session_name
    if not session_name then
      vim.notify('shared_session_name is required when tmux_mode = "window"', vim.log.levels.ERROR)
      return
    end
    local window_name = get_window_name(branch, path, config)
    handle_tmux_window(session_name, window_name, path, config)
  else
    local session_name = get_session_name(branch, path, config)
    handle_tmux_session(session_name, path, config)
  end
end

local function kill_tmux_target(branch, path, config)
  if config.tmux_mode == 'window' then
    local session_name = config.shared_session_name
    if not session_name then return end
    local window_name = get_window_name(branch, path, config)

    if not tmux_session_exists(session_name) then return end
    if not tmux_window_exists(session_name, window_name) then return end

    -- Count windows in the session
    local _, count_str = tmux_command(
      string.format("tmux list-windows -t %s 2>/dev/null | wc -l",
        vim.fn.shellescape(session_name)))
    local window_count = tonumber(vim.trim(count_str)) or 0

    if window_count <= 1 and config.auto_kill_empty_session then
      -- Last window — kill the entire session
      local ok, out = tmux_command(string.format('tmux kill-session -t %s',
        vim.fn.shellescape(session_name)))
      if ok then
        vim.notify('Killed tmux session: ' .. session_name)
      else
        vim.notify('Failed to kill session: ' .. out, vim.log.levels.ERROR)
      end
    else
      -- Kill just the window
      local ok, out = tmux_command(string.format('tmux kill-window -t %s:%s',
        vim.fn.shellescape(session_name),
        vim.fn.shellescape(window_name)))
      if ok then
        vim.notify('Killed tmux window: ' .. window_name)
      else
        vim.notify('Failed to kill window: ' .. out, vim.log.levels.ERROR)
      end
    end
  else
    local session_name = get_session_name(branch, path, config)
    if tmux_session_exists(session_name) then
      vim.notify('Killing tmux session: ' .. session_name)
      local ok, out = tmux_command(string.format('tmux kill-session -t %s', session_name))
      if not ok then
        vim.notify('Failed to kill session: ' .. out, vim.log.levels.ERROR)
      end
    end
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

      -- Handle tmux
      local config = get_project_config(path, M.config)
      dispatch_tmux(branch_name, path, config)
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
    
    -- Handle tmux
    local config = get_project_config(choice.path, M.config)
    dispatch_tmux(choice.branch, choice.path, config)
  end)
end

local function detect_default_branch()
  local success, output = tmux_command('git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null')
  if success and output ~= '' then
    return output:match('refs/remotes/origin/(.+)')
  end
  -- Fallback
  return 'main'
end

function M.delete_worktree()
  local worktrees = list_worktrees()
  if #worktrees == 0 then
    vim.notify('No worktrees found', vim.log.levels.WARN)
    return
  end
  
  -- Filter out bare repo entry and main branch worktree
  local default_branch = detect_default_branch()
  local deletable_worktrees = {}
  for _, wt in ipairs(worktrees) do
    if wt.branch and wt.branch ~= default_branch then
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
      
      -- Resolve config before deleting (path won't exist after removal)
      local config = get_project_config(choice.path, M.config)

      -- Delete the worktree
      local delete_cmd = string.format('git worktree remove %s', vim.fn.shellescape(choice.path))
      local success, result = tmux_command(delete_cmd)
      if not success then
        vim.notify('Failed to delete worktree: ' .. result, vim.log.levels.ERROR)
        return
      end

      vim.notify('Deleted worktree: ' .. choice.branch)

      -- Kill tmux target if configured
      if config.auto_kill_session then
        kill_tmux_target(choice.branch, choice.path, config)
      end
    end)
  end)
end

local function find_main_worktree_path(worktrees, target_branch)
  for _, wt in ipairs(worktrees) do
    if not wt.branch or wt.branch == target_branch then
      return wt.path
    end
  end
  -- Fallback: first worktree
  if #worktrees > 0 then
    return worktrees[1].path
  end
  return nil
end

function M.merge_worktree()
  local worktrees = list_worktrees()
  if #worktrees == 0 then
    vim.notify('No worktrees found', vim.log.levels.WARN)
    return
  end

  local target_branch = M.config.merge_target_branch or detect_default_branch()

  -- Filter to non-target worktrees
  local mergeable = {}
  for _, wt in ipairs(worktrees) do
    if wt.branch and wt.branch ~= target_branch then
      table.insert(mergeable, wt)
    end
  end

  if #mergeable == 0 then
    vim.notify('No worktrees to merge (only ' .. target_branch .. ' found)', vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, wt in ipairs(mergeable) do
    table.insert(items, {
      text = string.format('%s (%s)', wt.branch, wt.path),
      branch = wt.branch,
      path = wt.path,
    })
  end

  vim.ui.select(items, {
    prompt = 'Select worktree to merge into ' .. target_branch .. ':',
    format_item = function(item) return item.text end,
  }, function(choice)
    if not choice then return end

    -- Resolve project-specific config after worktree selection
    local config = get_project_config(choice.path, M.config)
    local cfg_target = config.merge_target_branch or target_branch

    -- Build strategies list with configured default first
    local all_strategies = { 'merge', 'rebase', 'squash' }
    local strategies = {}
    local default_strategy = config.default_merge_strategy or 'merge'
    table.insert(strategies, default_strategy)
    for _, s in ipairs(all_strategies) do
      if s ~= default_strategy then
        table.insert(strategies, s)
      end
    end

    vim.ui.select(strategies, {
      prompt = 'Merge strategy:',
    }, function(strategy)
      if not strategy then return end

      vim.ui.select({ 'Yes', 'No' }, {
        prompt = string.format('Merge %s into %s (%s) and cleanup?', choice.branch, cfg_target, strategy),
      }, function(confirm)
        if confirm ~= 'Yes' then return end

        -- Find the main worktree path for running merge commands
        local main_path = find_main_worktree_path(worktrees, cfg_target)
        if not main_path then
          vim.notify('Could not find main worktree path', vim.log.levels.ERROR)
          return
        end

        -- Checkout target branch in main worktree
        local checkout_cmd = string.format('git -C %s checkout %s',
          vim.fn.shellescape(main_path), vim.fn.shellescape(cfg_target))
        local ok, out = tmux_command(checkout_cmd)
        if not ok then
          vim.notify('Failed to checkout ' .. cfg_target .. ': ' .. out, vim.log.levels.ERROR)
          return
        end

        -- Execute merge strategy
        if strategy == 'merge' then
          local merge_cmd = string.format('git -C %s merge %s',
            vim.fn.shellescape(main_path), vim.fn.shellescape(choice.branch))
          ok, out = tmux_command(merge_cmd)
          if not ok then
            vim.notify('Merge failed (conflicts?): ' .. out, vim.log.levels.ERROR)
            tmux_command(string.format('git -C %s merge --abort', vim.fn.shellescape(main_path)))
            vim.notify('Merge aborted. Worktree and branch left intact.', vim.log.levels.WARN)
            return
          end
        elseif strategy == 'rebase' then
          -- Two-step: rebase feature onto target, then fast-forward target
          local rebase_cmd = string.format('git -C %s rebase %s',
            vim.fn.shellescape(choice.path), vim.fn.shellescape(cfg_target))
          ok, out = tmux_command(rebase_cmd)
          if not ok then
            vim.notify('Rebase failed (conflicts?): ' .. out, vim.log.levels.ERROR)
            tmux_command(string.format('git -C %s rebase --abort', vim.fn.shellescape(choice.path)))
            vim.notify('Rebase aborted. Worktree and branch left intact.', vim.log.levels.WARN)
            return
          end
          local ff_cmd = string.format('git -C %s merge --ff-only %s',
            vim.fn.shellescape(main_path), vim.fn.shellescape(choice.branch))
          ok, out = tmux_command(ff_cmd)
          if not ok then
            vim.notify('Fast-forward failed: ' .. out, vim.log.levels.ERROR)
            tmux_command(string.format('git -C %s merge --abort', vim.fn.shellescape(main_path)))
            return
          end
        elseif strategy == 'squash' then
          local squash_cmd = string.format('git -C %s merge --squash %s',
            vim.fn.shellescape(main_path), vim.fn.shellescape(choice.branch))
          ok, out = tmux_command(squash_cmd)
          if not ok then
            vim.notify('Squash merge failed (conflicts?): ' .. out, vim.log.levels.ERROR)
            tmux_command(string.format('git -C %s merge --abort', vim.fn.shellescape(main_path)))
            vim.notify('Merge aborted. Worktree and branch left intact.', vim.log.levels.WARN)
            return
          end
          -- Commit with safe argument passing
          local commit_msg = string.format("Squash merge branch '%s'", choice.branch)
          vim.fn.system({'git', '-C', main_path, 'commit', '-m', commit_msg})
          if vim.v.shell_error ~= 0 then
            vim.notify('Squash commit failed', vim.log.levels.ERROR)
            return
          end
        end

        vim.notify(string.format('Merged %s into %s (%s)', choice.branch, cfg_target, strategy))

        -- Cleanup: remove worktree
        local rm_cmd = string.format('git worktree remove %s', vim.fn.shellescape(choice.path))
        ok, out = tmux_command(rm_cmd)
        if not ok then
          vim.notify('Failed to remove worktree: ' .. out, vim.log.levels.ERROR)
          return
        end
        vim.notify('Removed worktree: ' .. choice.path)

        -- Cleanup: delete branch
        if config.auto_delete_branch then
          local del_cmd = string.format('git branch -d %s', vim.fn.shellescape(choice.branch))
          ok, out = tmux_command(del_cmd)
          if not ok then
            vim.notify('Failed to delete branch (not fully merged?): ' .. out, vim.log.levels.WARN)
          else
            vim.notify('Deleted branch: ' .. choice.branch)
          end
        end

        -- Cleanup: kill tmux target
        if config.auto_kill_session then
          kill_tmux_target(choice.branch, choice.path, config)
        end
      end)
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
  vim.api.nvim_create_user_command('WorktreeMerge', M.merge_worktree, {})
end

return M
