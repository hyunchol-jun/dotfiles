local vault_path = vim.fn.expand '~/Library/Mobile Documents/iCloud~md~obsidian/Documents/vimwiki'

return {
  {
    'epwalsh/obsidian.nvim',
    version = '*',
    lazy = true,
    ft = 'markdown',
    cond = function()
      return vim.fn.isdirectory(vault_path) == 1
    end,
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    opts = {
      workspaces = {
        {
          name = 'vimwiki',
          path = vault_path,
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
      { '<leader>nc', '<cmd>ObsidianToggleCheckbox<cr>', desc = '[N]otes [C]heckbox toggle' },
      { '<leader>nf', '<cmd>ObsidianFollowLink<cr>', desc = '[N]otes [F]ollow link' },
      { '<leader>nl', '<cmd>ObsidianLink<cr>', mode = 'v', desc = '[N]otes [L]ink selection' },
      { '<leader>ne', '<cmd>ObsidianExtractNote<cr>', mode = 'v', desc = '[N]otes [E]xtract to note' },
      { '<leader>ni', '<cmd>ObsidianPasteImg<cr>', desc = '[N]otes [I]mage paste' },
      { '<leader>np', '<cmd>ObsidianTemplate<cr>', desc = '[N]otes tem[P]late insert' },
      { '<leader>ny', '<cmd>ObsidianYesterday<cr>', desc = '[N]otes [Y]esterday daily' },
    },
  },
}
