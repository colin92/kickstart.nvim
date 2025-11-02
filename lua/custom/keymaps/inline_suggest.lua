local M = {}

local ns_id = vim.api.nvim_create_namespace 'inline_suggest'
local current_suggestion = nil

function M.show_suggestion()
  M.clear_suggestion()

  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  local line_length = #line

  local suggestion_lines = {
    'function greet(name) {',
    '  console.log("Hello, " + name);',
    '  return true;',
    '}',
  }

  local virt_lines = {}
  for i, text in ipairs(suggestion_lines) do
    table.insert(virt_lines, { { text, 'Comment' } })
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, row, line_length, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    hl_mode = 'combine',
  })

  current_suggestion = {
    buf = buf,
    extmark_id = extmark_id,
    lines = suggestion_lines,
    row = row,
  }
end

function M.clear_suggestion()
  if current_suggestion then
    pcall(vim.api.nvim_buf_del_extmark, current_suggestion.buf, ns_id, current_suggestion.extmark_id)
    current_suggestion = nil
  end
end

function M.accept_suggestion()
  if current_suggestion then
    local row = current_suggestion.row

    vim.api.nvim_buf_set_lines(0, row + 1, row + 1, false, current_suggestion.lines)

    local last_line_idx = row + #current_suggestion.lines
    local last_line = current_suggestion.lines[#current_suggestion.lines]
    vim.api.nvim_win_set_cursor(0, { last_line_idx + 1, #last_line })

    M.clear_suggestion()
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('InlineSuggest', { clear = true })

  vim.api.nvim_create_autocmd('CursorMovedI', {
    group = group,
    callback = function()
      vim.defer_fn(function()
        M.show_suggestion()
      end, 500)
    end,
  })

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    callback = function()
      M.clear_suggestion()
    end,
  })

  vim.keymap.set('i', '<C-r>', function()
    if current_suggestion then
      M.accept_suggestion()
    end
  end, { noremap = true, desc = 'Accept inline suggestion' })

  vim.keymap.set('i', '<C-e>', function()
    M.clear_suggestion()
  end, { noremap = true, desc = 'Dismiss inline suggestion' })
end

M.setup()

return M
