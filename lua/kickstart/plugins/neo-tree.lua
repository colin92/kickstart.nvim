-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  lazy = false,
  keys = {
    { '<leader>nn', ':Neotree toggle<CR>', desc = 'NeoTree reveal', silent = true },
    { '<leader>nd', ':Neotree document_symbols<CR>', desc = 'NeoTree reveal symbols', silent = true },
  },
  opts = {
    sources = {
      'filesystem',
      'buffers',
      'git_status',
      'document_symbols', -- Enable document symbols
    },

    -- Minimal document_symbols configuration
    document_symbols = {
      follow_cursor = true,
      window = {
        width = 30,
        position = 'right',
        mappings = {
          ['<cr>'] = 'jump_to_symbol',
          ['o'] = 'jump_to_symbol',
          ['<esc>'] = 'cancel',
        },
      },
    },
    filesystem = {
      window = {
        width = 30,
        mappings = {
          ['\\'] = 'close_window',
        },
      },
    },
  },
}
