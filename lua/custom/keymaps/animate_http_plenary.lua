local M = {}

local SERVER_URL = 'http://localhost:8080/stream'

function M.animate_http_stream()
  vim.cmd 'vsplit'
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false

  local current_text = ''

  vim.fn.jobstart({ 'curl', '--no-buffer', '-N', SERVER_URL }, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if data then
        for _, chunk in ipairs(data) do
          if chunk ~= '' then
            vim.schedule(function()
              current_text = current_text .. chunk
              local lines = vim.split(current_text, '\n', { plain = true })
              vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            end)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.schedule(function()
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Error: Failed to connect to server', 'Make sure the server is running on ' .. SERVER_URL })
        end)
      end
    end,
  })
end

vim.keymap.set('n', '<leader>ap', M.animate_http_stream, { desc = '[A]nimated [P]lenary stream demo' })

return M
