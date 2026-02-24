--- @class runtest.WindowLayout
--- @field vertical boolean
--- @field min number | nil
--- @field max number | nil
--- @field size number | nil

--- @param layout runtest.WindowLayout
--- @param new boolean | nil
--- @returns number
local function open_window(layout, new)
  local new_split = new and "new" or "split"
  local window_command = (layout.vertical and "v" or "") .. new_split

  if layout.size then
    local absolute_full_size = layout.vertical and vim.o.columns or vim.o.lines
    local absolute_size = absolute_full_size * layout.size

    if layout.min then
      absolute_size = math.max(absolute_size, layout.min)
    end

    if layout.max then
      absolute_size = math.min(absolute_size, layout.max)
    end

    vim.cmd(absolute_size .. window_command)
    local window = vim.api.nvim_get_current_win()
    return window
  else
    vim.cmd(window_command)
    local window = vim.api.nvim_get_current_win()

    if layout.min or layout.max then
      local absolute_size = layout.vertical and vim.api.nvim_win_get_height(window)
        or vim.api.nvim_win_get_width(window)
      local new_absolute_size = absolute_size

      if layout.min then
        new_absolute_size = math.max(absolute_size, layout.min)
      end

      if layout.max then
        new_absolute_size = math.min(absolute_size, layout.max)
      end

      if absolute_size ~= new_absolute_size then
        if layout.vertical then
          vim.api.nvim_win_set_height(window, new_absolute_size)
        else
          vim.api.nvim_win_set_width(window, new_absolute_size)
        end
      end
    end

    return window
  end
end

--- @param layout runtest.WindowLayout
--- @returns number
local function new_window(layout)
  return open_window(layout, true)
end

return {
  open_window = open_window,
  new_window = new_window
}
