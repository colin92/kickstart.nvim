local M = {}

function M.open_terraform_docs()
  local ts_utils = require 'nvim-treesitter.ts_utils'
  local node = ts_utils.get_node_at_cursor()

  if not node then
    vim.notify('No node found at cursor', vim.log.levels.WARN)
    return
  end

  while node do
    if node:type() == 'block' then
      local first_child = node:child(0)
      if first_child and first_child:type() == 'identifier' then
        local block_type = vim.treesitter.get_node_text(first_child, 0)

        if block_type == 'resource' then
          local resource_type_node = node:child(1)
          if resource_type_node and resource_type_node:type() == 'string_lit' then
            local resource_type = vim.treesitter.get_node_text(resource_type_node, 0)
            resource_type = resource_type:gsub('^"', ''):gsub('"$', '')

            local parts = vim.split(resource_type, '_', { plain = true })
            if #parts < 2 then
              vim.notify('Invalid resource type: ' .. resource_type, vim.log.levels.WARN)
              return
            end

            local provider = parts[1]
            local resource_name = table.concat(vim.list_slice(parts, 2), '_')

            if provider == 'google' then
              if resource_name:match '_iam_binding$' then
                resource_name = resource_name:gsub('_iam_binding$', '_iam')
              elseif resource_name:match '_iam_policy$' then
                resource_name = resource_name:gsub('_iam_policy$', '_iam')
              elseif resource_name:match '_iam_member$' then
                resource_name = resource_name:gsub('_iam_member$', '_iam')
              end
            end

            local url = string.format('https://registry.terraform.io/providers/hashicorp/%s/latest/docs/resources/%s', provider, resource_name)

            vim.ui.open(url)
            vim.notify('Opening: ' .. url, vim.log.levels.INFO)
            return
          end
        end
      end
    end
    node = node:parent()
  end

  vim.notify('Not inside a terraform resource block', vim.log.levels.WARN)
end

function M.open_module_picker()
  local ts_utils = require 'nvim-treesitter.ts_utils'
  local node = ts_utils.get_node_at_cursor()

  if not node then
    vim.notify('No node found at cursor', vim.log.levels.WARN)
    return
  end

  while node do
    if node:type() == 'block' then
      local first_child = node:child(0)
      if first_child and first_child:type() == 'identifier' then
        local block_type = vim.treesitter.get_node_text(first_child, 0)

        if block_type == 'module' then
          local body_node = nil
          for i = 0, node:child_count() - 1 do
            local child = node:child(i)
            if child and child:type() == 'body' then
              body_node = child
              break
            end
          end

          if not body_node then
            vim.notify('Could not find module body', vim.log.levels.WARN)
            return
          end

          local source_value = nil
          for i = 0, body_node:child_count() - 1 do
            local attr = body_node:child(i)
            if attr and attr:type() == 'attribute' then
              local attr_name_node = attr:child(0)
              if attr_name_node and attr_name_node:type() == 'identifier' then
                local attr_name = vim.treesitter.get_node_text(attr_name_node, 0)
                if attr_name == 'source' then
                  local expr_node = attr:child(2)
                  if expr_node then
                    source_value = vim.treesitter.get_node_text(expr_node, 0)
                    source_value = source_value:gsub('^"', ''):gsub('"$', '')
                    break
                  end
                end
              end
            end
          end

          if not source_value then
            vim.notify('Could not find source attribute in module', vim.log.levels.WARN)
            return
          end

          if source_value:match '^https?://' or source_value:match '^[%w-]+/[%w-]+/[%w-]+' then
            vim.notify('Module source is not a relative path: ' .. source_value, vim.log.levels.WARN)
            return
          end

          local current_file_dir = vim.fn.expand '%:p:h'
          local module_path = vim.fn.resolve(current_file_dir .. '/' .. source_value)

          if vim.fn.isdirectory(module_path) == 0 then
            vim.notify('Module path does not exist: ' .. module_path, vim.log.levels.WARN)
            return
          end

          require('telescope.builtin').find_files {
            cwd = module_path,
            prompt_title = 'Module Files: ' .. vim.fn.fnamemodify(module_path, ':t'),
          }
          return
        end
      end
    end
    node = node:parent()
  end

  vim.notify('Not inside a terraform module block', vim.log.levels.WARN)
end

function M.setup()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'terraform',
    callback = function(event)
      vim.keymap.set('n', '<leader>td', M.open_terraform_docs, { buffer = event.buf, desc = '[T]erraform [D]ocs for current resource' })
      vim.keymap.set('n', '<leader>tm', M.open_module_picker, { buffer = event.buf, desc = '[T]erraform [M]odule files picker' })
    end,
  })
end

M.setup()

return M
