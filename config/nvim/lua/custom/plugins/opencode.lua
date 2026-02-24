return {
  {
    'nickjvandyke/opencode.nvim',
    version = '*',
    dependencies = {
      {
        'folke/snacks.nvim',
        optional = true,
        opts = {
          input = {},
          picker = {},
        },
      },
    },
    keys = {
      {
        '<leader>oa',
        function()
          require('opencode').ask('@this: ', { submit = false })
        end,
        mode = { 'n', 'x' },
        desc = '[O]penCode [A]sk',
      },
      {
        '<leader>os',
        function()
          require('opencode').select()
        end,
        mode = { 'n', 'x' },
        desc = '[O]penCode [S]elect',
      },
      {
        '<leader>ot',
        function()
          require('opencode').toggle()
        end,
        desc = '[O]penCode [T]oggle',
      },
    },
    config = function()
      vim.g.opencode_opts = {}
      vim.o.autoread = true
    end,
  },
}
