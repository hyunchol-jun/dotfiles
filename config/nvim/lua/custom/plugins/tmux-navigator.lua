-- Ctrl+h/j/k/l between Neovim splits and tmux panes.
--
-- Where Hyprland runs (the Omarchy laptop) the same keys also carry on to other
-- app windows: from the last split, ~/dotfiles/bin/nav moves to the next tmux
-- pane or, past the edge of tmux, asks Hyprland to focus the next window.
-- See config/hypr/personal.lua. Everywhere else the plugin's own commands run.
local function edge_aware(direction)
  return function()
    if vim.fn.winnr() ~= vim.fn.winnr(direction) then
      vim.cmd.wincmd(direction)
    else
      vim.system({ vim.fn.expand '~/dotfiles/bin/nav', direction }, { detach = true })
    end
  end
end

local keys
if vim.fn.executable 'hyprctl' == 1 then
  keys = {
    { '<c-h>', edge_aware 'h', desc = 'Focus left (split, pane or window)' },
    { '<c-j>', edge_aware 'j', desc = 'Focus below (split, pane or window)' },
    { '<c-k>', edge_aware 'k', desc = 'Focus above (split, pane or window)' },
    { '<c-l>', edge_aware 'l', desc = 'Focus right (split, pane or window)' },
    { '<c-\\>', '<cmd><C-U>TmuxNavigatePrevious<cr>' },
  }
else
  keys = {
    { '<c-h>', '<cmd><C-U>TmuxNavigateLeft<cr>' },
    { '<c-j>', '<cmd><C-U>TmuxNavigateDown<cr>' },
    { '<c-k>', '<cmd><C-U>TmuxNavigateUp<cr>' },
    { '<c-l>', '<cmd><C-U>TmuxNavigateRight<cr>' },
    { '<c-\\>', '<cmd><C-U>TmuxNavigatePrevious<cr>' },
  }
end

return {
  {
    'christoomey/vim-tmux-navigator',
    cmd = {
      'TmuxNavigateLeft',
      'TmuxNavigateDown',
      'TmuxNavigateUp',
      'TmuxNavigateRight',
      'TmuxNavigatePrevious',
      'TmuxNavigatorProcessList',
    },
    keys = keys,
  },
}
