-- This is a simple plugin spec that just loads our custom module
return {
  'nvim-lua/plenary.nvim', -- dummy dependency to make lazy.nvim happy
  name = 'worktree-tmux',
  config = function()
    require('custom.worktree-tmux').setup()
  end,
  keys = {
    { '<leader>wtc', '<cmd>WorktreeCreate<cr>', desc = '[W]orktree [T]mux [C]reate' },
    { '<leader>wts', '<cmd>WorktreeSwitch<cr>', desc = '[W]orktree [T]mux [S]witch' },
    { '<leader>wtd', '<cmd>WorktreeDelete<cr>', desc = '[W]orktree [T]mux [D]elete' },
  },
}