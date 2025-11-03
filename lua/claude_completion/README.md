# Claude Completion for Neovim - Improved Version

An enhanced AI-powered code completion plugin for Neovim using Claude API.

## Key Improvements Over Original

### Performance & Reliability
- **Request cancellation**: Cancel ongoing requests when typing continues
- **Rate limiting**: Prevents API spam with minimum 500ms between requests
- **Timeout handling**: 30-second timeout with proper cleanup
- **Completion caching**: Cache recent completions for 1 minute
- **Context limiting**: Send only relevant context (configurable lines)
- **Better debouncing**: More intelligent idle detection

### Error Handling
- **Comprehensive error handling**: Handles API errors, network failures, timeouts
- **User notifications**: Clear error messages with vim.notify
- **Graceful degradation**: Continues working even with partial failures
- **Debug logging improvements**: Better structured logging with timestamps and source locations

### Features
- **Manual trigger**: `<C-Space>` to manually request completion
- **Smart triggers**: Configure auto-trigger characters (., :, (, {, [, space)
- **Minimum character threshold**: Avoid triggering on very short contexts
- **Better cursor positioning**: Properly handles insertion at cursor position
- **Cache management**: Commands to clear cache and check status
- **Virtual text highlighting**: Better visual distinction for suggestions

### User Experience
- **Status notifications**: Shows when suggestions are available
- **Debug window management**: Better debug window with auto-scroll
- **Configuration options**: Extensive customization through setup options
- **User commands**: `:ClaudeDebug`, `:ClaudeClearCache`, `:ClaudeStatus`

## Installation

### Using lazy.nvim

```lua
{
  "claude-completion",
  config = function()
    require("claude_completion").setup({
      -- Your configuration here
    })
  end
}
```

### Using packer.nvim

```lua
use {
  "claude-completion",
  config = function()
    require("claude_completion").setup({
      -- Your configuration here
    })
  end
}
```

## Configuration

```lua
require("claude_completion").setup({
  -- Debug and development
  debug_mode = false,                    -- Enable debug logging
  
  -- API Configuration
  model = 'claude-haiku-4-5-20251001',  -- Claude model to use
  max_tokens = 1024,                     -- Maximum tokens in response
  api_key_cmd = 'get_claude_api_key',   -- Command to retrieve API key
  api_timeout = 30000,                   -- API timeout in milliseconds
  
  -- Trigger Configuration
  debounce_ms = 1000,                    -- Delay before triggering completion
  auto_trigger_chars = { '.', ':', '(', '{', '[', ' ' },  -- Auto-trigger characters
  min_chars_before_cursor = 3,          -- Minimum characters before cursor
  
  -- Context Management
  max_context_lines = 100,               -- Lines of context to send
  
  -- Performance
  cache_completions = true,              -- Cache recent completions
  max_cache_size = 50,                   -- Maximum cache entries
})
```

## Key Mappings

| Mode | Key | Description |
|------|-----|-------------|
| Insert | `<C-y>` | Accept current suggestion |
| Insert | `<C-e>` | Dismiss current suggestion |
| Insert | `<C-Space>` | Manually trigger completion |
| Normal | `<leader>cd` | Open debug window (if debug mode enabled) |

## Commands

- `:ClaudeDebug` - Enable debug mode and open debug window
- `:ClaudeClearCache` - Clear completion cache and API key
- `:ClaudeStatus` - Show current plugin status

## API Key Setup

The plugin expects a command that returns your Claude API key. Default is `get_claude_api_key`.

Example shell script (`~/.local/bin/get_claude_api_key`):
```bash
#!/bin/bash
echo "your-api-key-here"
```

Or use a secure method:
```bash
#!/bin/bash
# Using password manager
pass show claude-api-key

# Or from environment variable
echo $CLAUDE_API_KEY

# Or from keychain
security find-generic-password -s "claude-api-key" -w
```

Make it executable:
```bash
chmod +x ~/.local/bin/get_claude_api_key
```

## Advanced Usage

### Custom Trigger Logic

You can override the trigger logic:

```lua
local claude = require("claude_completion")

-- Override the should_trigger_completion function
claude.should_trigger_completion = function()
  -- Your custom logic here
  local col = vim.fn.col('.')
  local line = vim.fn.getline('.')
  -- Only trigger after typing a dot followed by at least 2 chars
  return line:match('%.%w%w') ~= nil
end
```

### Programmatic Control

```lua
local claude = require("claude_completion")

-- Manually trigger completion
claude.request_completion()

-- Clear current suggestion
claude.clear_suggestion()

-- Cancel ongoing request
claude.cancel_request()

-- Accept completion programmatically
claude.accept_completion()
```

## Performance Tips

1. **Adjust context size**: Reduce `max_context_lines` for faster responses
2. **Use caching**: Keep `cache_completions = true` for repeated patterns
3. **Tune debounce**: Increase `debounce_ms` if you type quickly
4. **Selective triggers**: Limit `auto_trigger_chars` to essential ones
5. **Use Haiku model**: It's faster than Opus or Sonnet for completions

## Troubleshooting

### No completions appearing
1. Check API key: Run your `api_key_cmd` in terminal
2. Enable debug mode: `debug_mode = true` in setup
3. Check `:ClaudeStatus` for current state
4. Look for errors in debug window

### Completions are slow
1. Reduce `max_context_lines`
2. Switch to `claude-haiku-4-5` model
3. Check network connection
4. Enable caching

### Too many API calls
1. Increase `debounce_ms`
2. Increase `min_chars_before_cursor`
3. Reduce `auto_trigger_chars`

## Comparison with GitHub Copilot

| Feature | Claude Completion | GitHub Copilot |
|---------|------------------|----------------|
| Model | Claude (Anthropic) | Codex (OpenAI) |
| Customization | Highly configurable | Limited |
| Context Control | Full control | Automatic |
| Caching | Built-in | Built-in |
| Debug Mode | Comprehensive | Limited |
| Open Source | Yes | No |
| Cost | Pay per API call | Monthly subscription |

## License

MIT

## Contributing

Contributions welcome! Key areas for improvement:
- Multi-line completion preview
- LSP integration for better context
- Treesitter-aware context extraction
- Streaming API support
- Multiple suggestion cycling