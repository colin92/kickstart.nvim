local M = {}

local DEBUG_MODE = false

local ns_id = vim.api.nvim_create_namespace 'claude_completion'
local model = 'claude-haiku-4-5-20251001'
local current_suggestion = nil
local pending_request = nil
local last_cursor_pos = nil
local is_requesting = false
local debug_buf = nil
local debug_lines = {}

local function debug_log(msg)
  if not DEBUG_MODE then
    return
  end

  local timestamp = os.date '%H:%M:%S'
  local sanitized_msg = msg:gsub('\n', ' ')
  table.insert(debug_lines, string.format('[%s] %s', timestamp, sanitized_msg))

  if debug_buf and vim.api.nvim_buf_is_valid(debug_buf) then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(debug_buf) then
        vim.api.nvim_buf_set_lines(debug_buf, 0, -1, false, debug_lines)
      end
    end)
  end
end

local function is_debug_buffer(buf)
  return buf == debug_buf
end

local function create_debug_buffer()
  if not DEBUG_MODE then
    return
  end

  if debug_buf and vim.api.nvim_buf_is_valid(debug_buf) then
    return
  end

  local original_win = vim.api.nvim_get_current_win()

  vim.cmd 'vsplit'
  debug_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, debug_buf)

  vim.bo[debug_buf].buftype = 'nofile'
  vim.bo[debug_buf].bufhidden = 'hide'
  vim.bo[debug_buf].swapfile = false
  vim.api.nvim_buf_set_name(debug_buf, 'Claude Completion Debug')

  debug_lines = { '=== Claude Completion Debug Log ===' }
  vim.api.nvim_buf_set_lines(debug_buf, 0, -1, false, debug_lines)

  vim.api.nvim_set_current_win(original_win)

  debug_log 'Debug mode initialized'
end

function M.clear_suggestion()
  if current_suggestion then
    debug_log 'Clearing suggestion'
    if vim.api.nvim_buf_is_valid(current_suggestion.buf) then
      pcall(vim.api.nvim_buf_del_extmark, current_suggestion.buf, ns_id, current_suggestion.extmark_id)
    end
    current_suggestion = nil
  end
end

function M.parse_completion_response(response)
  debug_log('Parsing response (length: ' .. #response .. ')')
  local suggestions = {}

  for suggestion_block in response:gmatch '**Suggestion %d+:**.-```%w+\n(.-)\n```' do
    table.insert(suggestions, suggestion_block)
  end

  if #suggestions == 0 then
    for code_block in response:gmatch '```%w*\n(.-)\n```' do
      table.insert(suggestions, code_block)
      break
    end
  end

  debug_log('Found ' .. #suggestions .. ' suggestions')
  if suggestions[1] then
    debug_log('First suggestion preview: ' .. suggestions[1]:sub(1, 100))
  end

  return suggestions[1]
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

  local lines = vim.split(completion_text, '\n', { plain = true })
  debug_log('Showing completion with ' .. #lines .. ' lines')

  local virt_lines = {}
  for i, text in ipairs(lines) do
    table.insert(virt_lines, { { text, 'Comment' } })
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    hl_mode = 'combine',
  })

  current_suggestion = {
    buf = buf,
    extmark_id = extmark_id,
    lines = lines,
    row = row,
  }
end

function M.accept_completion()
  if current_suggestion then
    debug_log 'Accepting completion'
    local row = current_suggestion.row

    vim.api.nvim_buf_set_lines(0, row + 1, row + 1, false, current_suggestion.lines)

    local last_line_idx = row + #current_suggestion.lines
    local last_line = current_suggestion.lines[#current_suggestion.lines]
    vim.api.nvim_win_set_cursor(0, { last_line_idx + 1, #last_line })

    M.clear_suggestion()
  end
end

function M.request_completion()
  if is_requesting then
    debug_log 'Request already in progress, skipping'
    return
  end

  local buf = vim.api.nvim_get_current_buf()

  if is_debug_buffer(buf) then
    debug_log 'In debug buffer, skipping completion request'
    return
  end

  is_requesting = true
  M.clear_suggestion()

  debug_log 'Starting completion request'

  local handle = io.popen 'get_claude_api_key'
  local api_key = handle:read '*a'
  handle:close()
  api_key = api_key:gsub('^%s*(.-)%s*$', '%1')

  if not api_key or api_key == '' then
    debug_log 'API key not found'
    is_requesting = false
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2]

  local filename = vim.api.nvim_buf_get_name(buf)
  local filetype = vim.bo[buf].filetype

  debug_log('File: ' .. filename .. ', Type: ' .. filetype .. ', Pos: ' .. row .. ':' .. col)

  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local before_cursor = vim.list_slice(all_lines, 1, row - 1)
  table.insert(before_cursor, all_lines[row]:sub(1, col))

  local after_cursor = { all_lines[row]:sub(col + 1) }
  for i = row + 1, #all_lines do
    table.insert(after_cursor, all_lines[i])
  end

  local before_text = table.concat(before_cursor, '\n')
  local after_text = table.concat(after_cursor, '\n')

  local prompt = string.format(
    [[
## Context
File: %s
Language: %s
Cursor Position: Line %d, Column %d

## File Content
```%s
%s<<<CURSOR>>>%s
```

## Instructions
1. Analyze the code context before and after the cursor
2. Consider:
   - The current scope (function, class, block)
   - Variable names and types in scope
   - Code patterns and style used in the file
   - Incomplete statements or expressions
   - Logical next steps in the code flow

3. Provide a single, most relevant completion suggestion
4. The suggestion should:
   - Be contextually appropriate
   - Follow the existing code style
   - Be syntactically correct
   - Be concise (1-5 lines maximum)

## Output Format
Provide only the completion code in a fenced code block, nothing else.
]],
    filename,
    filetype,
    row,
    col,
    filetype,
    before_text,
    after_text
  )

  local request_body = vim.json.encode {
    model = model,
    max_tokens = 1024,
    system = 'You are an intelligent code completion assistant. A user is actively editing a file and needs suggestions for what to write next. Provide concise, contextually appropriate code completions.',
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
  }

  local response_text = ''

  debug_log 'Sending API request to Claude'

  vim.fn.jobstart({
    'curl',
    '-s',
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
    on_exit = function(_, exit_code)
      is_requesting = false
      debug_log('API request completed with exit code: ' .. exit_code)

      if exit_code == 0 and response_text ~= '' then
        vim.schedule(function()
          local ok, response = pcall(vim.json.decode, response_text)
          if ok and response.content and response.content[1] and response.content[1].text then
            debug_log('Response text: ' .. response.content[1].text:sub(1, 200))
            local completion = M.parse_completion_response(response.content[1].text)
            if completion then
              M.show_completion(completion)
            else
              debug_log 'Failed to parse completion from response'
            end
          else
            debug_log 'Failed to decode JSON response or missing content'
            debug_log 'Response:'
            debug_log(response_text)
          end
        end)
      else
        debug_log 'Request failed or empty response'
      end
    end,
  })
end

function M.setup()
  if DEBUG_MODE then
    create_debug_buffer()
  end

  local group = vim.api.nvim_create_augroup('ClaudeCompletion', { clear = true })

  vim.api.nvim_create_autocmd({ 'CursorMovedI', 'TextChangedI' }, {
    group = group,
    callback = function()
      local buf = vim.api.nvim_get_current_buf()

      if is_debug_buffer(buf) then
        return
      end

      M.clear_suggestion()

      if pending_request then
        vim.fn.timer_stop(pending_request)
        pending_request = nil
      end

      local current_pos = vim.api.nvim_win_get_cursor(0)

      pending_request = vim.fn.timer_start(1000, function()
        if not is_requesting then
          debug_log 'Cursor idle timeout triggered'
          M.request_completion()
        end
        pending_request = nil
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ 'InsertLeave', 'ModeChanged' }, {
    group = group,
    callback = function()
      local mode = vim.api.nvim_get_mode().mode
      if mode ~= 'i' and mode ~= 'ic' then
        debug_log('Left insert mode (mode: ' .. mode .. '), clearing suggestions and pending requests')
        M.clear_suggestion()
        if pending_request then
          vim.fn.timer_stop(pending_request)
          pending_request = nil
        end
        is_requesting = false
      end
    end,
  })

  vim.keymap.set('i', '<C-r>', function()
    if current_suggestion then
      M.accept_completion()
    end
  end, { noremap = true, desc = 'Accept Claude completion' })

  vim.keymap.set('i', '<C-e>', function()
    M.clear_suggestion()
  end, { noremap = true, desc = 'Dismiss Claude completion' })

  vim.keymap.set('n', '<leader>cd', function()
    if DEBUG_MODE then
      create_debug_buffer()
    else
      vim.notify('Debug mode is disabled. Set DEBUG_MODE = true in claude_completion.lua', vim.log.levels.WARN)
    end
  end, { noremap = true, desc = '[C]laude completion [D]ebug' })
end

M.setup()

return M
