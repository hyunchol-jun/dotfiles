return {
  'akinsho/bufferline.nvim',
  version = '*',
  dependencies = 'nvim-tree/nvim-web-devicons',
  config = function()
    vim.opt.termguicolors = true
    vim.keymap.set('n', '<S-l>', '<CMD>BufferLineCycleNext<CR>')
    vim.keymap.set('n', '<S-h>', '<CMD>BufferLineCyclePrev<CR>')
    require('bufferline').setup {}
  end,
}
