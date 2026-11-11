-- worktree-tmux: Neovim front end for `wt` (~/dotfiles/bin/wt).
--
-- All the real work — creating the worktree, seeding files from main, opening
-- the tmux window, fast removal, merging — lives in that script so the command
-- line and agents (the `wt` skill) do exactly what these keymaps do. This file
-- only asks the questions and reports the answers.
--
-- Per-project behaviour (tmux mode, symlinks, agent command) is configured in
-- ~/.config/wt/projects/<project>.sh, not here.
local M = {}

local function wt_bin()
  if vim.fn.executable('wt') == 1 then return 'wt' end
  return vim.fn.expand('~/dotfiles/bin/wt')
end

local function notify(text, level)
  text = vim.trim(text or '')
  if text ~= '' then vim.notify(text, level or vim.log.levels.INFO) end
end

-- Run `wt <args>` without blocking the UI. cb(code, stdout, stderr) runs on
-- the main loop. wt keeps stdout machine-readable; its messages are on stderr.
local function wt(args, cb)
  local cmd = { wt_bin() }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true, cwd = vim.fn.getcwd() }, function(obj)
    vim.schedule(function()
      cb(obj.code, vim.trim(obj.stdout or ''), vim.trim(obj.stderr or ''))
    end)
  end)
end

-- `wt` messages minus git's own chatter ("Preparing worktree ...")
local function wt_lines(stderr)
  local keep = {}
  for line in stderr:gmatch('[^\n]+') do
    local msg = line:match('^wt: (.*)')
    if msg then table.insert(keep, msg) end
  end
  return #keep > 0 and table.concat(keep, '\n') or stderr
end

-- Switch this tmux client to the target wt printed. Goes through `:!` rather
-- than a background job so tmux picks the client this Neovim is running in.
local function switch_to(target)
  if not vim.env.TMUX or target == '' then return end
  vim.cmd('silent !tmux switch-client -t ' .. vim.fn.shellescape(target, true))
  vim.cmd('redraw!')
end

-- cb(list of { branch, path, text }) — real, checked-out worktrees only
local function list_worktrees(cb)
  wt({ 'ls' }, function(code, out, err)
    if code ~= 0 then
      notify(wt_lines(err), vim.log.levels.ERROR)
      return
    end
    local items = {}
    for line in out:gmatch('[^\n]+') do
      local branch, mark, path, flag = line:match('^([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$')
      if branch and flag ~= 'prunable' then
        table.insert(items, {
          branch = branch,
          path = path,
          text = string.format('%s %s (%s)', mark == '-' and ' ' or '●', branch, path),
        })
      end
    end
    cb(items)
  end)
end

local function default_branch()
  local out = vim.fn.system('git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null')
  local name = vim.trim(out):match('^origin/(.+)$')
  return (vim.v.shell_error == 0 and name) or 'main'
end

-- Pick a worktree other than the default branch's, then cb(item)
local function pick_worktree(prompt, cb, include_default)
  list_worktrees(function(items)
    local skip = not include_default and default_branch() or nil
    items = vim.tbl_filter(function(item)
      return item.branch ~= skip and (include_default or item.branch ~= '(detached)')
    end, items)
    if #items == 0 then
      notify('No worktrees to choose from', vim.log.levels.WARN)
      return
    end
    vim.ui.select(items, {
      prompt = prompt,
      format_item = function(item) return item.text end,
    }, function(choice)
      if choice then cb(choice) end
    end)
  end)
end

function M.create_worktree()
  vim.ui.input({ prompt = 'Branch name: ' }, function(branch)
    if not branch or branch == '' then return end

    local function create(extra)
      local args = { 'new', branch, '--detach' }
      vim.list_extend(args, extra or {})
      wt(args, function(code, out, err)
        if code == 0 then
          notify(wt_lines(err))
          switch_to(out)
        elseif code == 3 then
          -- the branch already exists and is behind the default branch
          vim.ui.select({ 'Reuse it anyway', 'Cancel' }, { prompt = wt_lines(err) }, function(choice)
            if choice == 'Reuse it anyway' then
              create({ '--reuse' })
            else
              notify('Worktree creation cancelled (pick a new branch name for current code)',
                vim.log.levels.WARN)
            end
          end)
        else
          notify(wt_lines(err), vim.log.levels.ERROR)
        end
      end)
    end

    create()
  end)
end

function M.switch_worktree()
  pick_worktree('Select worktree:', function(choice)
    wt({ 'open', choice.path, '--detach' }, function(code, out, err)
      if code ~= 0 then
        notify(wt_lines(err), vim.log.levels.ERROR)
        return
      end
      switch_to(out)
    end)
  end, true)
end

function M.delete_worktree()
  pick_worktree('Select worktree to delete:', function(choice)
    local keep, drop = 'Delete worktree, keep branch', 'Delete worktree and branch'
    vim.ui.select({ drop, keep, 'Cancel' }, {
      prompt = string.format('Delete worktree %s?', choice.branch),
    }, function(answer)
      if answer ~= keep and answer ~= drop then return end

      local function remove(force)
        local args = { 'rm', choice.path }
        if answer == drop then table.insert(args, '--branch') end
        if force then table.insert(args, '--force') end
        notify('Deleting worktree: ' .. choice.branch .. ' ...')
        wt(args, function(code, _, err)
          if code == 0 then
            notify(wt_lines(err))
          elseif code == 4 then
            vim.ui.select({ 'Cancel', 'Delete anyway (discard changes)' }, {
              prompt = string.format("Worktree '%s' has uncommitted changes. Delete anyway?", choice.branch),
            }, function(dchoice)
              if dchoice == 'Delete anyway (discard changes)' then remove(true) end
            end)
          elseif code == 5 then
            -- worktree is gone; `git branch -d` refused the unmerged branch
            notify(wt_lines(err), vim.log.levels.WARN)
            vim.ui.select({ 'Cancel', 'Force delete (-D, discards its commits)' }, {
              prompt = string.format("Branch '%s' is not fully merged. Force delete?", choice.branch),
            }, function(fchoice)
              if fchoice ~= 'Force delete (-D, discards its commits)' then return end
              local out = vim.fn.system({ 'git', 'branch', '-D', choice.branch })
              if vim.v.shell_error == 0 then
                notify('Force-deleted branch: ' .. choice.branch)
              else
                notify('Failed to delete branch: ' .. out, vim.log.levels.ERROR)
              end
            end)
          else
            notify(wt_lines(err), vim.log.levels.ERROR)
          end
        end)
      end

      remove(false)
    end)
  end)
end

function M.merge_worktree()
  pick_worktree('Select worktree to merge into ' .. default_branch() .. ':', function(choice)
    vim.ui.select({ 'merge', 'rebase', 'squash' }, { prompt = 'Merge strategy:' }, function(strategy)
      if not strategy then return end
      vim.ui.select({ 'Yes', 'No' }, {
        prompt = string.format('Merge %s (%s) and clean up?', choice.branch, strategy),
      }, function(confirm)
        if confirm ~= 'Yes' then return end
        wt({ 'merge', choice.path, '--strategy', strategy }, function(code, _, err)
          notify(wt_lines(err), code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
        end)
      end)
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('WorktreeCreate', M.create_worktree, {})
  vim.api.nvim_create_user_command('WorktreeSwitch', M.switch_worktree, {})
  vim.api.nvim_create_user_command('WorktreeDelete', M.delete_worktree, {})
  vim.api.nvim_create_user_command('WorktreeMerge', M.merge_worktree, {})
end

return M
