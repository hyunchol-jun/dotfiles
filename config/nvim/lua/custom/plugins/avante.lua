return {
  "yetone/avante.nvim",
  event = "VeryLazy",
  version = false, -- Never set this value to "*"! Never!
  opts = {
    -- add any opts here
    -- for example
    provider = "openai",
    -- claude = {
    --   endpoint    = "https://api.anthropic.com",   -- leave as-is for official API
    --   model       = "claude-sonnet-4-20250514",    -- *exact* model id (see docs)
    --   temperature = 0,                             -- deterministic output
    --   timeout     = 30000,                         -- ms; bump if you use 200 k ctx
    --   -- disable_tools = true,                    -- uncomment if Avante’s tool calls blow past your quota
    -- },
    openai = {
      endpoint = "https://api.openai.com/v1",
      model = "gpt-4.1-mini-2025-04-14", -- your desired model (or use gpt-4o, etc.)
      timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
      temperature = 0,
      --reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
    },
    windows = {
      -- everything under `sidebar_header` affects the very first line of
      -- the sidebar.  These are all *optional* – Avante falls back to true.
      sidebar_header = {
        show_provider   = true,   -- “Claude Sonnet-4”
        show_token_cost = true,   -- “$0.0021”
        show_token_io   = true,   -- “↥ 312 / ↧ 45”
        align           = "center",  -- left|center|right
      },
    },
  },
  -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
  build = "make",
  -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    --- The below dependencies are optional,
    "echasnovski/mini.pick", -- for file_selector provider mini.pick
    "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
    "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
    "ibhagwan/fzf-lua", -- for file_selector provider fzf
    "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
    "zbirenbaum/copilot.lua", -- for providers='copilot'
    {
      -- support for image pasting
      "HakonHarnes/img-clip.nvim",
      event = "VeryLazy",
      opts = {
        -- recommended settings
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          -- required for Windows users
          use_absolute_path = true,
        },
      },
    },
    {
      -- Make sure to set this up properly if you have lazy=true
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
        file_types = { "markdown", "Avante" },
      },
      ft = { "markdown", "Avante" },
    },
  },
}
