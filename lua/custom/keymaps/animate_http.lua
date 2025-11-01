local M = {}

local SERVER_URL = 'localhost'
local SERVER_PORT = 8080
local SERVER_PATH = '/stream'

function M.animate_http_stream()
  vim.cmd 'vsplit'
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false

  local current_text = ''
  local uv = vim.loop
  local client = uv.new_tcp()

  client:connect('127.0.0.1', SERVER_PORT, function(err)
    if err then
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Error: Failed to connect to server', err })
      end)
      return
    end

    local request = string.format('GET %s HTTP/1.1\r\nHost: %s:%d\r\nConnection: close\r\n\r\n', SERVER_PATH, SERVER_URL, SERVER_PORT)
    client:write(request)

    local headers_done = false

    client:read_start(function(read_err, chunk)
      if read_err then
        vim.schedule(function()
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Error reading from server: ' .. read_err })
        end)
        client:close()
        return
      end

      if chunk then
        if not headers_done then
          local header_end = chunk:find '\r\n\r\n'
          if header_end then
            headers_done = true
            chunk = chunk:sub(header_end + 4)
          else
            return
          end
        end

        vim.schedule(function()
          current_text = current_text .. chunk
          local lines = vim.split(current_text, '\n', { plain = true })
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          -- if #lines > 0 and lines[#lines] then
          --   vim.api.nvim_win_set_cursor(0, { #lines, #lines[#lines]:len() })
          -- end
        end)
      else
        client:close()
      end
    end)
  end)
end

vim.keymap.set('n', '<leader>ah', M.animate_http_stream, { desc = '[A]nimated [H]TTP stream demo' })

return M
