local M = {}

function M.animate_text()
  -- The text to be animated character by character
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

  -- Create a vertical split window
  vim.cmd 'vsplit'
  -- Create a new unlisted, scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  -- Set the new buffer in the current window
  vim.api.nvim_win_set_buf(0, buf)

  -- Configure buffer options to make it temporary and non-persistent
  vim.bo[buf].buftype = 'nofile' -- Buffer is not associated with a file
  vim.bo[buf].bufhidden = 'wipe' -- Delete buffer when hidden
  vim.bo[buf].swapfile = false -- Don't create a swapfile

  -- Split the text into individual lines
  local lines = vim.split(text, '\n', { plain = true })
  -- Track which line we're currently writing
  local current_line = 1
  -- Track the column position (character index) in the current line
  local current_col = 0

  -- Clear the buffer to start with empty content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

  -- Recursive function that writes one character at a time
  local function write_char()
    -- Stop if we've written all lines
    if current_line > #lines then
      return
    end

    -- Get the current line text
    local line = lines[current_line]

    -- If starting a new line, create an empty line in the buffer
    if current_col == 0 then
      vim.api.nvim_buf_set_lines(buf, current_line - 1, current_line - 1, false, { '' })
    end

    -- If there are more characters to write in this line
    if current_col < #line then
      -- Move to the next character
      current_col = current_col + 1
      -- Get the substring from the start up to current position
      local text_so_far = line:sub(1, current_col)
      -- Update the buffer with the text written so far
      vim.api.nvim_buf_set_lines(buf, current_line - 1, current_line, false, { text_so_far })
      -- Move cursor to the end of the written text
      -- vim.api.nvim_win_set_cursor(0, { current_line, current_col })
      -- Schedule next character after 20ms
      vim.defer_fn(write_char, 20)
    else
      -- Finished the current line, move to next line
      current_line = current_line + 1
      current_col = 0
      -- Add a slightly longer delay between lines (50ms)
      vim.defer_fn(write_char, 50)
    end
  end

  -- Start the animation
  write_char()
end

vim.keymap.set('n', '<leader>aw', M.animate_text, { desc = '[A]nimated [W]riting demo' })

return M
