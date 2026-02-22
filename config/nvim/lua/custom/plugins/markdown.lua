return {
  {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' },
    ft = 'markdown',
    opts = {},
    keys = {
      { '<leader>mt', '<cmd>RenderMarkdown toggle<cr>', desc = 'Toggle render markdown' },
    },
  },
}
