local vault_path = vim.fn.expand '~/Library/Mobile Documents/iCloud~md~obsidian/Documents/vimwiki'

local function open_context_daily(context, template)
  local ok, obsidian = pcall(require, 'obsidian')
  if not ok then
    vim.notify('obsidian.nvim is not available', vim.log.levels.ERROR)
    return
  end

  local client = obsidian.get_client()
  local title = os.date '%Y-%m-%d'
  local dir = string.format('contexts/%s/daily', context)
  local note = client:create_note {
    title = title,
    id = title,
    dir = dir,
    template = template,
  }

  client:open_note(note)
end

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
      templates = {
        folder = 'templates',
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
      {
        '<leader>ndp',
        function()
          open_context_daily('personal', 'daily-personal')
        end,
        desc = '[N]otes [D]aily [P]ersonal',
      },
      {
        '<leader>ndi',
        function()
          open_context_daily('implentio', 'daily-implentio')
        end,
        desc = '[N]otes [D]aily [I]mplentio',
      },
      { '<leader>no', '<cmd>ObsidianQuickSwitch<cr>', desc = '[N]otes [O]pen' },
      { '<leader>nr', '<cmd>ObsidianNewFromTemplate reference<cr>', desc = '[N]otes new [R]eference' },
      { '<leader>ns', '<cmd>ObsidianSearch<cr>', desc = '[N]otes [S]earch' },
      { '<leader>nb', '<cmd>ObsidianBacklinks<cr>', desc = '[N]otes [B]acklinks' },
      { '<leader>nt', '<cmd>ObsidianTags<cr>', desc = '[N]otes [T]ags' },
      { '<leader>nc', '<cmd>ObsidianToggleCheckbox<cr>', desc = '[N]otes [C]heckbox toggle' },
      { '<leader>nj', '<cmd>ObsidianNewFromTemplate project<cr>', desc = '[N]otes new pro[J]ect' },
      { '<leader>nf', '<cmd>ObsidianFollowLink<cr>', desc = '[N]otes [F]ollow link' },
      { '<leader>nl', '<cmd>ObsidianLink<cr>', mode = 'v', desc = '[N]otes [L]ink selection' },
      { '<leader>ne', '<cmd>ObsidianExtractNote<cr>', mode = 'v', desc = '[N]otes [E]xtract to note' },
      { '<leader>nI', '<cmd>ObsidianPasteImg<cr>', desc = '[N]otes paste [I]mage' },
      { '<leader>np', '<cmd>ObsidianTemplate<cr>', desc = '[N]otes tem[P]late insert' },
      { '<leader>nw', '<cmd>ObsidianNewFromTemplate weekly-review<cr>', desc = '[N]otes new [W]eekly review' },
    },
  },
}
