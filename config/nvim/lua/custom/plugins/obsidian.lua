return {
  {
    'epwalsh/obsidian.nvim',
    version = '*',
    lazy = true,
    ft = 'markdown',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    opts = {
      workspaces = {
        {
          name = 'vimwiki',
          path = vim.fn.expand '~/Library/Mobile Documents/iCloud~md~obsidian/Documents/vimwiki',
        },
      },
      daily_notes = {
        folder = 'daily',
        date_format = '%Y-%m-%d',
      },
      completion = {
        nvim_cmp = true,
        min_chars = 2,
      },
      new_notes_location = 'current_dir',
      preferred_link_style = 'wiki',
      -- Disable UI since render-markdown.nvim handles markdown rendering
      ui = {
        enable = false,
      },
    },
    keys = {
      { '<leader>nn', '<cmd>ObsidianNew<cr>', desc = '[N]otes [N]ew' },
      { '<leader>no', '<cmd>ObsidianQuickSwitch<cr>', desc = '[N]otes [O]pen' },
      { '<leader>ns', '<cmd>ObsidianSearch<cr>', desc = '[N]otes [S]earch' },
      { '<leader>nd', '<cmd>ObsidianToday<cr>', desc = '[N]otes [D]aily today' },
      { '<leader>nb', '<cmd>ObsidianBacklinks<cr>', desc = '[N]otes [B]acklinks' },
      { '<leader>nt', '<cmd>ObsidianTags<cr>', desc = '[N]otes [T]ags' },
    },
  },
}
