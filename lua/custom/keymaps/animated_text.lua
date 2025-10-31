local M = {}

function M.animate_text()
  local text = [[
In the heart of the digital realm, where code flows like rivers through silicon valleys,
developers craft their dreams into reality. Each keystroke is a brushstroke on the canvas
of possibility, transforming abstract thoughts into tangible applications that shape our
world. The editor becomes an extension of the mind, a tool that bridges imagination and
implementation. Through the gentle glow of the screen, ideas take form, bugs are vanquished,
and software emerges—not just as lines of code, but as solutions to problems yet unsolved.
This is the art of programming, where logic meets creativity, and where every function,
every variable, every carefully placed semicolon contributes to something greater than
the sum of its parts.
]]

  vim.cmd 'vsplit'
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false

  local lines = vim.split(text, '\n', { plain = true })
  local current_line = 1
  local current_col = 0

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

  local function write_char()
    if current_line > #lines then
      return
    end

    local line = lines[current_line]

    if current_col == 0 then
      vim.api.nvim_buf_set_lines(buf, current_line - 1, current_line - 1, false, { '' })
    end

    if current_col < #line then
      current_col = current_col + 1
      local text_so_far = line:sub(1, current_col)
      vim.api.nvim_buf_set_lines(buf, current_line - 1, current_line, false, { text_so_far })
      -- vim.api.nvim_win_set_cursor(0, { current_line, current_col })
      vim.defer_fn(write_char, 20)
    else
      current_line = current_line + 1
      current_col = 0
      vim.defer_fn(write_char, 50)
    end
  end

  write_char()
end

vim.keymap.set('n', '<leader>aw', M.animate_text, { desc = '[A]nimated [W]riting demo' })

return M
