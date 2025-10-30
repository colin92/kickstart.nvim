local M = {}

function M.insert_from_modal()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row = cursor_pos[1]
  local col = cursor_pos[2]
  local original_buf = vim.api.nvim_get_current_buf()

  local buf = vim.api.nvim_create_buf(false, true)

  local width = 60
  local height = 1
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Write something! ',
    title_pos = 'center',
  })

  vim.bo[buf].buftype = 'prompt'
  vim.fn.prompt_setprompt(buf, '> ')

  vim.cmd 'startinsert'

  local function close_and_insert()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = lines[1] or ''
    text = text:gsub('^> ', '')

    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })

    if text ~= '' then
      vim.api.nvim_set_current_buf(original_buf)
      vim.api.nvim_buf_set_text(original_buf, row - 1, col, row - 1, col, { text })
      vim.api.nvim_win_set_cursor(0, { row, col + #text })
    end
  end

  local function close_without_insert()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.api.nvim_set_current_buf(original_buf)
  end

  vim.keymap.set('i', '<CR>', close_and_insert, { buffer = buf, nowait = true })
  vim.keymap.set('i', '<Esc>', close_without_insert, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Esc>', close_without_insert, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<C-C>', close_without_insert, { buffer = buf, nowait = true })
end

vim.keymap.set('n', '<leader>ab', M.insert_from_modal, { desc = '[A]dd text from modal [B]ox' })

return M
