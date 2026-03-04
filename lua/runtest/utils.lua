--- @param ... table
local function build_command_line(...)
  local command_line = {}


  for i, arguments in pairs({ ... }) do
    for i, arg in pairs(arguments or {}) do
      if type(i) == "string" then
        if type(arg) == "boolean" then
          if arg then
            table.insert(command_line, i)
          end
        else
          table.insert(command_line, i)
          table.insert(command_line, arg)
        end
      else
        table.insert(command_line, arg)
      end
    end
  end

  return command_line
end

--- @return string | nil
local function get_visual_text()
  local mode = vim.fn.mode()

  if mode ~= "v" and mode ~= "V" and mode ~= "" then
    return nil
  end

  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")

  -- getpos returns {bufnum, lnum, col, off} (1-based)
  local start_line, start_col = start_pos[2], start_pos[3]
  local end_line, end_col = end_pos[2], end_pos[3]

  if start_line == 0 then
    return nil
  end

  -- ensure start is before end
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return nil
  end

  lines[#lines] = lines[#lines]:sub(1, end_col)
  lines[1] = lines[1]:sub(start_col)

  return table.concat(lines, "\n")
end

return {
  build_command_line = build_command_line,
  get_visual_text = get_visual_text,
}
