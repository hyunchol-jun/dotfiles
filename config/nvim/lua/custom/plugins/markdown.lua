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
  {
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
    ft = 'markdown',
    build = 'cd app && npm install',
    keys = {
      { '<leader>mp', '<cmd>MarkdownPreviewToggle<cr>', desc = 'Toggle markdown preview (browser)' },
    },
  },
}
