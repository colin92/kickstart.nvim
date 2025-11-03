return {
  -- dir = vim.fn.stdpath 'config' .. '/lua/claude_completion',
  -- name = 'claude_completion',
  -- event = 'InsertEnter',
  -- config = function()
  --   require('claude_completion').setup {
  --     api_key_cmd = 'get_claude_api_key',
  --     model = 'claude-haiku-4-5-20251001',
  --     debug = true,
  --     debounce_ms = 1000,
  --     cache_completions = true,
  --   }
  -- end,
  -- keys = {
  --   { '<C-y>', mode = 'i', desc = 'Accept Claude completion' },
  --   { '<C-e>', mode = 'i', desc = 'Dismiss Claude completion' },
  --   { '<C-r>', mode = 'i', desc = 'Trigger Claude completion' },
  -- },
  -- cmd = { 'ClaudeDebug', 'ClaudeClearCache', 'ClaudeStatus' },
}
