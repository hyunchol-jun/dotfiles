-- This is a simple plugin spec that just loads our custom module
return {
  name = 'worktree-tmux',
  dir = vim.fn.stdpath('config') .. '/lua/custom',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('custom.worktree-tmux').setup()
  end,
  keys = {
    { '<leader>wtc', '<cmd>WorktreeCreate<cr>', desc = '[W]orktree [T]mux [C]reate' },
    { '<leader>wts', '<cmd>WorktreeSwitch<cr>', desc = '[W]orktree [T]mux [S]witch' },
    { '<leader>wtd', '<cmd>WorktreeDelete<cr>', desc = '[W]orktree [T]mux [D]elete' },
  },
}
