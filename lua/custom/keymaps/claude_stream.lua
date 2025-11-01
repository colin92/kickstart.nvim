local M = {}

local function parse_sse_event(line, buffer)
  if line:match '^event:' then
    buffer.event = line:match '^event:%s*(.+)'
  elseif line:match '^data:' then
    buffer.data = line:match '^data:%s*(.+)'
    if buffer.event == 'content_block_delta' and buffer.data then
      local ok, json = pcall(vim.json.decode, buffer.data)
      if ok and json.delta and json.delta.text then
        buffer.event = nil
        buffer.data = nil
        return json.delta.text
      end
    end
  elseif line == '' then
    buffer.event = nil
    buffer.data = nil
  end
  return nil
end

function M.stream_claude_response(prompt)
  local handle = io.popen('get_claude_api_key')
  local api_key = handle:read '*a'
  handle:close()
  api_key = api_key:gsub('^%s*(.-)%s*$', '%1')
  
  if not api_key or api_key == '' then
    vim.notify('Failed to get Claude API key from get_claude_api_key command', vim.log.levels.ERROR)
    return
  end

  vim.cmd 'vsplit'
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'

  local current_text = ''
  local sse_buffer = { event = nil, data = nil }
  local partial_line = ''

  local request_body = vim.json.encode {
    model = 'claude-sonnet-4-5-20250929',
    max_tokens = 4096,
    stream = true,
    messages = {
      {
        role = 'user',
        content = prompt,
      },
    },
  }

  local job_id = vim.fn.jobstart({
    'curl',
    '-s',
    '--no-buffer',
    '-N',
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
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if data then
        for _, chunk in ipairs(data) do
          if chunk ~= '' then
            partial_line = partial_line .. chunk .. '\n'
            local lines = vim.split(partial_line, '\n', { plain = true })

            for i = 1, #lines - 1 do
              local text = parse_sse_event(lines[i], sse_buffer)
              if text then
                vim.schedule(function()
                  current_text = current_text .. text
                  local display_lines = vim.split(current_text, '\n', { plain = true })
                  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
                end)
              end
            end

            partial_line = lines[#lines]
          end
        end
      end
    end,

    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code ~= 0 then
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Error: Failed to connect to Anthropic API', 'Exit code: ' .. exit_code, 'Current text: ' .. current_text })
        elseif current_text == '' then
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Error: No content received from API' })
        end
      end)
    end,
  })
  
  if job_id <= 0 then
    vim.notify('Failed to start job', vim.log.levels.ERROR)
  end
end

function M.prompt_and_stream()
  local prompt_buf = vim.api.nvim_create_buf(false, true)

  local width = 80
  local height = 5
  local win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Ask Claude ',
    title_pos = 'center',
  })

  vim.bo[prompt_buf].buftype = 'nofile'
  vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { '' })

  vim.cmd 'startinsert'

  local function submit_prompt()
    local lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
    local prompt = table.concat(lines, '\n'):gsub('^%s*(.-)%s*$', '%1')

    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(prompt_buf, { force = true })

    if prompt ~= '' then
      M.stream_claude_response(prompt)
    end
  end

  local function cancel_prompt()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(prompt_buf, { force = true })
  end

  vim.keymap.set('n', '<CR>', submit_prompt, { buffer = prompt_buf, nowait = true })
  vim.keymap.set('n', '<Esc>', cancel_prompt, { buffer = prompt_buf, nowait = true })
  vim.keymap.set('n', '<C-c>', cancel_prompt, { buffer = prompt_buf, nowait = true })
  vim.keymap.set('i', '<C-CR>', submit_prompt, { buffer = prompt_buf, nowait = true })
  vim.keymap.set('i', '<Esc>', cancel_prompt, { buffer = prompt_buf, nowait = true })
end

vim.keymap.set('n', '<leader>ac', M.prompt_and_stream, { desc = '[A]sk [C]laude' })

return M
