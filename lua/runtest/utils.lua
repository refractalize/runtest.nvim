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

local function get_current_visual_range(mode)
  local mode = vim.fn.mode()

  if mode ~= "v" and mode ~= "V" and mode ~= "" then
    return nil
  end

  local start_position = vim.fn.getpos("v")
  local end_position = vim.fn.getpos(".")

  if
    start_position[2] > end_position[2]
    or (start_position[2] == end_position[2] and start_position[3] > end_position[3])
  then
    start_position, end_position = end_position, start_position
  end

  return {
    start_position = start_position,
    end_position = end_position,
    mode = mode,
  }
end

local function get_visual_lines()
  local range = get_current_visual_range()
  if range == nil then
    return nil
  end

  local start_position = range.start_position
  local end_position = range.end_position
  local mode = range.mode

  local lines = vim.fn.getbufline("%", start_position[2], end_position[2])

  if mode == "v" then
    if #lines == 1 then
      lines[1] = string.sub(lines[1], start_position[3], end_position[3])
      return lines
    else
      lines[1] = string.sub(lines[1], start_position[3])
      lines[#lines] = string.sub(lines[#lines], 1, end_position[3])
      return lines
    end
  elseif mode == "V" then
    return lines
  elseif mode == "" then
    return vim.tbl_map(function(line)
      return string.sub(line, start_position[3], end_position[3])
    end, lines)
  else
    return nil
  end
end

local function get_visual_text()
  local lines = get_visual_lines()

  if lines ~= nil then
    return vim.fn.join(lines, "\n")
  else
    return nil
  end
end

return {
  build_command_line = build_command_line,
  get_visual_text = get_visual_text,
}
