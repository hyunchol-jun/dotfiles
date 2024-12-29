return {
  "oysandvik94/curl.nvim",
  cmd = { "CurlOpen" },
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = true,
  keys = {
    {
      "<leader>cc",
      "<cmd>CurlOpen<cr>",
      { desc = "Open a curl tab scoped to the current working directory" },
    },
    {
      "<leader>co",
      "<cmd>CurlOpen global<cr>",
      { desc = "Open a curl tab with gloabl scope" },
    },
  },
}
