local M = {}

-- nth fibonacci function

-- Configuration
M.config = {
  debug_mode = true,
  model = 'claude-haiku-4-5-20251001',
  max_tokens = 1024,
  debounce_ms = 1000,
  max_context_lines = 100, -- Limit context to avoid huge API requests
  api_key_cmd = 'get_claude_api_key',
  api_timeout = 30000, -- 30 seconds timeout
  auto_trigger_chars = { '.', ':', '(', '{', '[', ' ' }, -- Characters that trigger completion
  min_chars_before_cursor = 0, -- Minimum characters before cursor to trigger
  cache_completions = true, -- Cache recent completions
  max_cache_size = 50,
}

-- State management
local state = {
  ns_id = vim.api.nvim_create_namespace 'claude_completion',
  current_suggestion = nil,
  pending_request = nil,
  last_cursor_pos = nil,
  is_requesting = false,
  debug_buf = nil,
  debug_lines = {},
  completion_cache = {}, -- Cache for recent completions
  last_request_time = 0,
  api_key = nil, -- Cache API key
  request_job = nil, -- Track current job for cancellation
}

-- Utility functions
local function debug_log(msg)
  if not M.config.debug_mode then
    return
  end

  local timestamp = os.date '%H:%M:%S.%3N'
  local info = debug.getinfo(2, 'Sl')
  local location = string.format('%s:%d', info.short_src:match '[^/]+$', info.currentline)
  local sanitized_msg = msg:gsub('\n', '\\n'):gsub('\r', '\\r')

  table.insert(state.debug_lines, string.format('[%s] [%s] %s', timestamp, location, sanitized_msg))

  -- Keep log size manageable
  if #state.debug_lines > 1000 then
    table.remove(state.debug_lines, 1)
  end

  if state.debug_buf and vim.api.nvim_buf_is_valid(state.debug_buf) then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(state.debug_buf) then
        vim.bo[state.debug_buf].modifiable = true
        pcall(vim.api.nvim_buf_set_lines, state.debug_buf, 0, -1, false, state.debug_lines)
        -- Auto-scroll to bottom
        local win = vim.fn.bufwinid(state.debug_buf)
        if win ~= -1 then
          vim.api.nvim_win_set_cursor(win, { #state.debug_lines, 0 })
        end
      end
    end)
  end
end

local function is_debug_buffer(buf)
  return buf == state.debug_buf
end

local function create_debug_window()
  if not M.config.debug_mode then
    return
  end

  if state.debug_buf and vim.api.nvim_buf_is_valid(state.debug_buf) then
    -- If buffer exists, just show it in a window
    local wins = vim.fn.win_findbuf(state.debug_buf)
    if #wins == 0 then
      vim.cmd 'vsplit'
      vim.api.nvim_win_set_buf(0, state.debug_buf)
    end
    return
  end

  local original_win = vim.api.nvim_get_current_win()

  vim.cmd 'vsplit'
  vim.cmd 'wincmd L' -- Move to the right
  vim.cmd 'vertical resize 60' -- Set width

  state.debug_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, state.debug_buf)

  vim.bo[state.debug_buf].buftype = 'nofile'
  vim.bo[state.debug_buf].bufhidden = 'hide'
  vim.bo[state.debug_buf].swapfile = false
  vim.api.nvim_buf_set_name(state.debug_buf, 'Claude Completion Debug')

  state.debug_lines = { '=== Claude Completion Debug Log ===', '' }
  vim.api.nvim_buf_set_lines(state.debug_buf, 0, -1, false, state.debug_lines)
  vim.bo[state.debug_buf].modifiable = false

  vim.api.nvim_set_current_win(original_win)

  debug_log 'Debug mode initialized'
end

local function get_api_key()
  if state.api_key then
    return state.api_key
  end

  local handle = io.popen(M.config.api_key_cmd)
  if not handle then
    debug_log 'Failed to execute API key command'
    return nil
  end

  local api_key = handle:read '*a'
  handle:close()

  api_key = api_key:gsub('^%s*(.-)%s*$', '%1')

  if api_key and api_key ~= '' then
    state.api_key = api_key -- Cache it
    debug_log 'API key retrieved and cached'
    return api_key
  end

  debug_log 'API key not found or empty'
  return nil
end

local function get_cache_key(context)
  -- Create a simple cache key from the context
  local before = context.before_text:sub(-50) -- Last 50 chars
  local after = context.after_text:sub(1, 50) -- First 50 chars
  return vim.fn.sha256(before .. '|' .. after .. '|' .. context.filetype)
end

local function get_cached_completion(context)
  if not M.config.cache_completions then
    return nil
  end

  local key = get_cache_key(context)
  local cached = state.completion_cache[key]

  if cached and (vim.loop.now() - cached.timestamp) < 60000 then -- 1 minute cache
    debug_log 'Using cached completion'
    return cached.completion
  end

  return nil
end

local function cache_completion(context, completion)
  if not M.config.cache_completions then
    return
  end

  local key = get_cache_key(context)
  state.completion_cache[key] = {
    completion = completion,
    timestamp = vim.loop.now(),
  }

  -- Clean old cache entries
  local count = 0
  for _ in pairs(state.completion_cache) do
    count = count + 1
  end

  if count > M.config.max_cache_size then
    -- Remove oldest entry
    local oldest_key, oldest_time = nil, vim.loop.now()
    for k, v in pairs(state.completion_cache) do
      if v.timestamp < oldest_time then
        oldest_key = k
        oldest_time = v.timestamp
      end
    end
    if oldest_key then
      state.completion_cache[oldest_key] = nil
    end
  end
end

function M.clear_suggestion()
  if state.current_suggestion then
    debug_log 'Clearing suggestion'
    if vim.api.nvim_buf_is_valid(state.current_suggestion.buf) then
      pcall(vim.api.nvim_buf_del_extmark, state.current_suggestion.buf, state.ns_id, state.current_suggestion.extmark_id)
    end
    state.current_suggestion = nil
  end
end

function M.cancel_request()
  if state.request_job then
    debug_log 'Cancelling ongoing request'
    vim.fn.jobstop(state.request_job)
    state.request_job = nil
    state.is_requesting = false
  end
end

function M.parse_completion_response(response)
  debug_log('Parsing response (length: ' .. #response .. ')')

  -- Try multiple parsing strategies
  local suggestions = {}

  -- Strategy 1: Look for numbered suggestions
  for suggestion_block in response:gmatch '**Suggestion %d+:**.-```%w+\n(.-)\n```' do
    table.insert(suggestions, suggestion_block)
  end

  -- Strategy 2: Look for any code blocks
  if #suggestions == 0 then
    for code_block in response:gmatch '```%w*\n(.-)\n```' do
      table.insert(suggestions, code_block)
    end
  end

  -- Strategy 3: Look for indented code (4 spaces or tab)
  if #suggestions == 0 then
    for line in response:gmatch '    ([^\n]+)' do
      table.insert(suggestions, line)
    end
    if #suggestions > 0 then
      suggestions = { table.concat(suggestions, '\n') }
    end
  end

  debug_log('Found ' .. #suggestions .. ' suggestions')

  if suggestions[1] then
    -- Clean up the suggestion
    local cleaned = suggestions
      [1]
      :gsub('^%s+', '') -- Remove leading whitespace
      :gsub('%s+$', '') -- Remove trailing whitespace

    debug_log('First suggestion preview: ' .. cleaned:sub(1, 100))
    return cleaned
  end

  return nil
end

function M.show_completion(completion_text)
  M.clear_suggestion()

  if not completion_text or completion_text == '' then
    debug_log 'No completion text to show'
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local lines = vim.split(completion_text, '\n', { plain = true })
  debug_log('Showing completion with ' .. #lines .. ' lines')

  -- Create virtual text with proper positioning
  local virt_lines = {}
  for i, text in ipairs(lines) do
    local highlight = i == 1 and 'CmpItemAbbrMatch' or 'Comment'
    table.insert(virt_lines, { { text, highlight } })
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(buf, state.ns_id, row, col, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    hl_mode = 'combine',
    priority = 1000, -- High priority to show over other virtual text
  })

  state.current_suggestion = {
    buf = buf,
    extmark_id = extmark_id,
    lines = lines,
    row = row,
    col = col,
  }

  -- Show notification that suggestion is available
  vim.notify('Claude suggestion available (Ctrl+Y to accept)', vim.log.levels.INFO, {
    timeout = 1000,
    title = 'Claude Completion',
  })
end

function M.accept_completion()
  if not state.current_suggestion then
    debug_log 'No completion to accept'
    return
  end

  debug_log 'Accepting completion'
  local row = state.current_suggestion.row
  local col = state.current_suggestion.col

  -- Get current line
  local current_line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] or ''

  -- Insert at cursor position
  local before = current_line:sub(1, col)
  local after = current_line:sub(col + 1)

  local new_lines = {}
  for i, line in ipairs(state.current_suggestion.lines) do
    if i == 1 then
      table.insert(new_lines, before .. line)
    else
      table.insert(new_lines, line)
    end
  end

  -- Add the remainder of the original line to the last line
  new_lines[#new_lines] = new_lines[#new_lines] .. after

  -- Replace the current line and insert new ones
  vim.api.nvim_buf_set_lines(0, row, row + 1, false, new_lines)

  -- Move cursor to end of inserted text
  local last_line_idx = row + #new_lines - 1
  local last_line = new_lines[#new_lines]
  local new_col = #last_line - #after
  vim.api.nvim_win_set_cursor(0, { last_line_idx + 1, new_col })

  M.clear_suggestion()
end

function M.should_trigger_completion()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local col = cursor[2]

  -- Check minimum characters
  if col < M.config.min_chars_before_cursor then
    return false
  end

  -- Check for trigger characters
  if #M.config.auto_trigger_chars > 0 then
    local line = vim.api.nvim_get_current_line()
    local char = line:sub(col, col)

    for _, trigger in ipairs(M.config.auto_trigger_chars) do
      if char == trigger then
        return true
      end
    end
  end

  return true -- Default to true if no specific triggers configured
end

function M.get_context_lines(all_lines, row, max_lines)
  local start_row = math.max(1, row - max_lines)
  local end_row = math.min(#all_lines, row + max_lines)

  local before = {}
  for i = start_row, row - 1 do
    table.insert(before, all_lines[i])
  end

  local after = {}
  for i = row + 1, end_row do
    table.insert(after, all_lines[i])
  end

  return before, after
end

function M.request_completion()
  if state.is_requesting then
    debug_log 'Request already in progress, skipping'
    return
  end

  local buf = vim.api.nvim_get_current_buf()

  if is_debug_buffer(buf) then
    debug_log 'In debug buffer, skipping completion request'
    return
  end

  if not M.should_trigger_completion() then
    debug_log 'Completion trigger conditions not met'
    return
  end

  -- Rate limiting
  local now = vim.loop.now()
  if now - state.last_request_time < 500 then -- Min 500ms between requests
    debug_log 'Rate limiting: too soon since last request'
    return
  end
  state.last_request_time = now

  state.is_requesting = true
  M.clear_suggestion()

  debug_log 'Starting completion request'

  local api_key = get_api_key()
  if not api_key then
    state.is_requesting = false
    vim.notify('API key not found. Please configure ' .. M.config.api_key_cmd, vim.log.levels.ERROR)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2]

  local filename = vim.api.nvim_buf_get_name(buf)
  local filetype = vim.bo[buf].filetype

  debug_log('File: ' .. filename .. ', Type: ' .. filetype .. ', Pos: ' .. row .. ':' .. col)

  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Get limited context
  local before_lines, after_lines = M.get_context_lines(all_lines, row, M.config.max_context_lines)

  -- Add current line parts
  local current_line = all_lines[row]
  table.insert(before_lines, current_line:sub(1, col))

  local after_cursor = { current_line:sub(col + 1) }
  for _, line in ipairs(after_lines) do
    table.insert(after_cursor, line)
  end

  local context = {
    before_text = table.concat(before_lines, '\n'),
    after_text = table.concat(after_cursor, '\n'),
    filetype = filetype,
    filename = filename,
    row = row,
    col = col,
  }

  -- Check cache
  local cached = get_cached_completion(context)
  if cached then
    state.is_requesting = false
    M.show_completion(cached)
    return
  end

  local prompt = string.format(
    [[## Context
File: %s
Language: %s
Cursor Position: Line %d, Column %d

## Code Before Cursor
```%s
%s
```

## Code After Cursor
```%s
%s
```

## Instructions
Analyze the code context and provide a single, contextually appropriate completion.

Requirements:
- Complete the current line or block naturally
- Match the existing code style and indentation
- Be concise (1-5 lines maximum)
- Consider variable names, types, and patterns in scope
- Provide only the code to be inserted, no explanations

Output only the completion code in a fenced code block.]],
    filename,
    filetype,
    row,
    col,
    filetype,
    context.before_text,
    filetype,
    context.after_text
  )

  local request_body = vim.json.encode {
    model = M.config.model,
    max_tokens = M.config.max_tokens,
    temperature = 0.3, -- Lower temperature for more focused completions
    system = 'You are a precise code completion assistant. Provide only the exact code needed to complete the current context. Be concise and contextually accurate.',
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
  }

  local response_text = ''
  local timeout_timer = nil

  debug_log 'Sending API request to Claude'

  -- Set timeout
  timeout_timer = vim.fn.timer_start(M.config.api_timeout, function()
    if state.request_job then
      vim.fn.jobstop(state.request_job)
      state.request_job = nil
      state.is_requesting = false
      vim.notify('Claude API request timed out', vim.log.levels.WARN)
      debug_log 'Request timed out'
    end
  end)

  state.request_job = vim.fn.jobstart({
    'curl',
    '-s',
    '-m',
    tostring(M.config.api_timeout / 1000), -- curl timeout in seconds
    'https://api.anthropic.com/v1/messages',
    '-H',
    'content-type: application/json',
    '-H',
    'x-api-key: ' .. api_key,
    '-H',
    'anthropic-version: 2023-06-01',
    '-d',
    request_body,
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, chunk in ipairs(data) do
          if chunk ~= '' then
            response_text = response_text .. chunk
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, chunk in ipairs(data) do
          if chunk ~= '' then
            debug_log('STDERR: ' .. chunk)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      if timeout_timer then
        vim.fn.timer_stop(timeout_timer)
      end

      state.request_job = nil
      state.is_requesting = false
      debug_log('API request completed with exit code: ' .. exit_code)

      if exit_code == 0 and response_text ~= '' then
        vim.schedule(function()
          local ok, response = pcall(vim.json.decode, response_text)
          if ok and response then
            if response.error then
              local error_msg = response.error.message or 'Unknown API error'
              vim.notify('Claude API error: ' .. error_msg, vim.log.levels.ERROR)
              debug_log('API Error: ' .. vim.inspect(response.error))
            elseif response.content and response.content[1] and response.content[1].text then
              debug_log('Response text: ' .. response.content[1].text:sub(1, 200))
              local completion = M.parse_completion_response(response.content[1].text)
              if completion then
                cache_completion(context, completion)
                M.show_completion(completion)
              else
                debug_log 'Failed to parse completion from response'
              end
            else
              debug_log 'Unexpected response format'
              debug_log('Response: ' .. vim.inspect(response))
            end
          else
            debug_log 'Failed to decode JSON response'
            debug_log('Raw response: ' .. response_text:sub(1, 500))
          end
        end)
      else
        debug_log('Request failed with exit code ' .. exit_code)
        if exit_code == 28 then
          vim.notify('Claude API request timed out', vim.log.levels.WARN)
        elseif exit_code ~= 0 then
          vim.notify('Claude API request failed', vim.log.levels.ERROR)
        end
      end
    end,
  })
end

function M.setup(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})

  if M.config.debug_mode then
    create_debug_window()
  end

  local group = vim.api.nvim_create_augroup('ClaudeCompletion', { clear = true })

  -- Trigger completion on idle in insert mode
  vim.api.nvim_create_autocmd({ 'CursorHoldI' }, {
    group = group,
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if not is_debug_buffer(buf) and not state.is_requesting then
        debug_log 'CursorHoldI triggered'
        M.request_completion()
      end
    end,
  })

  -- Clear on cursor movement
  vim.api.nvim_create_autocmd({ 'CursorMovedI', 'TextChangedI' }, {
    group = group,
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if is_debug_buffer(buf) then
        return
      end

      M.clear_suggestion()
      M.cancel_request() -- Cancel any ongoing request

      if state.pending_request then
        vim.fn.timer_stop(state.pending_request)
        state.pending_request = nil
      end

      -- Debounced request
      state.pending_request = vim.fn.timer_start(M.config.debounce_ms, function()
        if not state.is_requesting then
          debug_log 'Debounce timer triggered'
          M.request_completion()
        end
        state.pending_request = nil
      end)
    end,
  })

  -- Clean up on leaving insert mode
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'ModeChanged' }, {
    group = group,
    callback = function()
      local mode = vim.api.nvim_get_mode().mode
      if mode ~= 'i' and mode ~= 'ic' then
        debug_log('Left insert mode (mode: ' .. mode .. '), cleaning up')
        M.clear_suggestion()
        M.cancel_request()
        if state.pending_request then
          vim.fn.timer_stop(state.pending_request)
          state.pending_request = nil
        end
        state.is_requesting = false
      end
    end,
  })

  -- Clean up on buffer unload
  vim.api.nvim_create_autocmd({ 'BufUnload' }, {
    group = group,
    callback = function()
      M.clear_suggestion()
      M.cancel_request()
    end,
  })

  -- Key mappings
  vim.keymap.set('i', '<C-r>', function()
    if state.current_suggestion then
      M.accept_completion()
    else
      return '<C-r>' -- Fallback to default behavior
    end
  end, { noremap = true, expr = true, desc = 'Accept Claude completion' })

  vim.keymap.set('i', '<C-e>', function()
    if state.current_suggestion then
      M.clear_suggestion()
    else
      return '<C-e>' -- Fallback to default behavior
    end
  end, { noremap = true, expr = true, desc = 'Dismiss Claude completion' })

  -- Manual trigger
  vim.keymap.set('i', '<C-t>', function()
    M.cancel_request()
    M.request_completion()
  end, { noremap = true, desc = 'Trigger Claude completion' })

  -- Debug commands
  vim.api.nvim_create_user_command('ClaudeDebug', function()
    M.config.debug_mode = true
    create_debug_window()
  end, { desc = 'Open Claude completion debug window' })

  vim.api.nvim_create_user_command('ClaudeClearCache', function()
    state.completion_cache = {}
    state.api_key = nil
    vim.notify('Claude completion cache cleared', vim.log.levels.INFO)
  end, { desc = 'Clear Claude completion cache' })

  vim.api.nvim_create_user_command('ClaudeStatus', function()
    local status_lines = {
      'Claude Completion Status:',
      '  Model: ' .. M.config.model,
      '  Debug Mode: ' .. tostring(M.config.debug_mode),
      '  Cache Enabled: ' .. tostring(M.config.cache_completions),
      '  Cache Size: ' .. vim.tbl_count(state.completion_cache),
      '  Is Requesting: ' .. tostring(state.is_requesting),
      '  API Key: ' .. (state.api_key and 'Loaded' or 'Not loaded'),
    }
    vim.notify(table.concat(status_lines, '\n'), vim.log.levels.INFO)
  end, { desc = 'Show Claude completion status' })

  debug_log 'Claude completion setup complete'
end

return M
