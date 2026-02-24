local sign_ns_id = vim.api.nvim_create_namespace("runtest.sign")
local line_ns_id = vim.api.nvim_create_namespace("runtest.line")
local output_buffer_marker = "runtest_output_buffer"
local highlight = "RunTestLine"
vim.api.nvim_set_hl(0, highlight, {})

local sign_highlight = "RunTestSign"
vim.api.nvim_set_hl(0, sign_highlight, {
  link = "DiagnosticSignWarn",
})

--- @class runtest.OutputProfile
--- @field file_patterns (string | fun(line: string): ([string, string, string, string] | nil))[]
--- @field external_file_patterns (string | fun(line: string): (boolean))[]
--- @field output_window runtest.OutputWindowConfig | nil
--- @field filetype string | nil
--- @field render_header boolean | nil
--- @field colorize boolean | nil

--- @class OutputBufferOptions
--- @field profile runtest.OutputProfile | nil
--- @field header_lines string[] | nil

--- @class Entry
--- @field filename string
--- @field line_number number
--- @field column_number number
--- @field output_line_number number
--- @field output_line string
--- @field buf number
--- @field ext_mark? number

--- @class runtest.OutputBuffer
--- @field buf number
--- @field entries Entry[]
--- @field current_entry_index number | nil
--- @field profile runtest.OutputProfile
--- @field header_lines string[]
--- @field modifying_buffer boolean
local OutputBuffer = {}
OutputBuffer.__index = OutputBuffer

--- @param buf number
--- @return boolean
function OutputBuffer.is_output_buffer(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.b[buf][output_buffer_marker] == true
end

--- @param filename string
--- @return boolean
function OutputBuffer:is_external_filename(filename)
  for i, pattern in ipairs(self.profile.external_file_patterns or {}) do
    if type(pattern) == "function" then
      return pattern(filename)
    else
      local match_index = vim.fn.match(filename, pattern)
      if match_index ~= -1 then
        return true
      end
    end
  end

  return false
end

--- @param line string
--- @return [string, string, string, string] | nil
function OutputBuffer:match_filename(line)
  for i, pattern in ipairs(self.profile.file_patterns or {}) do
    if type(pattern) == "function" then
      return pattern(line)
    else
      local matches = vim.fn.matchlist(line, pattern)
      if matches[1] ~= nil then
        return matches
      end
    end
  end
end

--- @param entry Entry
--- @return number | nil
function create_entry_ext_mark(entry)
  local success, extmark_id =
    pcall(vim.api.nvim_buf_set_extmark, entry.buf, sign_ns_id, entry.line_number - 1, entry.column_number - 1, {})
  if success then
    return extmark_id
  end
end

--- @param buf number
function OutputBuffer:load_buffer_ext_marks(buf)
  for i, entry in ipairs(self.entries) do
    if entry.buf == buf and not entry.ext_mark then
      entry.ext_mark = create_entry_ext_mark(entry)
    end
  end
end

function OutputBuffer:goto_entry(entry)
  if vim.fn.filereadable(entry.filename) > 0 then
    if vim.fn.bufloaded(entry.buf) == 0 then
      vim.fn.bufload(entry.buf)
      self:load_buffer_ext_marks(entry.buf)
    end

    local target_window_id = self:get_target_window_id(entry.buf)
    vim.api.nvim_set_current_win(target_window_id)

    if vim.api.nvim_get_current_buf() ~= entry.buf then
      vim.api.nvim_set_current_buf(entry.buf)
    end

    if entry.ext_mark == nil then
      return
    end

    local position = vim.api.nvim_buf_get_extmark_by_id(entry.buf, sign_ns_id, entry.ext_mark, {})
    vim.api.nvim_win_set_cursor(target_window_id, { position[1] + 1, position[2] })

    self.current_entry_index = entry.index
    self:highlight_entry(entry)

    local current_window = self:current_window()
    if current_window then
      vim.api.nvim_win_set_cursor(current_window, { entry.output_line_number, 0 })
    end
  end
end

function OutputBuffer:highlight_entry(entry)
  vim.api.nvim_buf_clear_namespace(self.buf, line_ns_id, 0, -1)
  vim.api.nvim_buf_add_highlight(self.buf, line_ns_id, "QuickFixLine", entry.output_line_number - 1, 0, -1)
end

function OutputBuffer:get_next_entry(allow_external_file)
  local current_window = self:current_window()

  if current_window then
    local current_line_number = vim.api.nvim_win_get_cursor(current_window)[1]

    for i, entry in ipairs(self.entries) do
      if entry.output_line_number > current_line_number then
        if allow_external_file or not self:is_external_filename(entry.filename) then
          return entry, i
        end
      end
    end
  else
    if not self.current_entry_index then
      self.current_entry_index = 0
    end

    local entry_index = self.current_entry_index + 1

    while entry_index <= #self.entries do
      local entry = self.entries[entry_index]
      if allow_external_file or not self:is_external_filename(entry.filename) then
        return entry, entry_index
      end
      entry_index = entry_index + 1
    end
  end
end

function OutputBuffer:goto_next_entry(allow_external_file)
  local entry, index = self:get_next_entry(allow_external_file)

  if entry then
    self.current_entry_index = index
    self:goto_entry(entry)
  end
end

function OutputBuffer:get_previous_entry(allow_external_file)
  local current_window = self:current_window()

  if current_window then
    local current_line_number = vim.api.nvim_win_get_cursor(current_window)[1]

    for i = #self.entries, 1, -1 do
      local entry = self.entries[i]
      if entry.output_line_number < current_line_number then
        if allow_external_file or not self:is_external_filename(entry.filename) then
          return entry, i
        end
      end
    end
  else
    if not self.current_entry_index then
      self.current_entry_index = #self.entries + 1
    end

    local entry_index = self.current_entry_index - 1

    while entry_index >= 1 do
      local entry = self.entries[entry_index]
      if allow_external_file or not self:is_external_filename(entry.filename) then
        return entry, entry_index
      end
      entry_index = entry_index - 1
    end
  end
end

function OutputBuffer:goto_previous_entry(allow_external_file)
  local entry, index = self:get_previous_entry(allow_external_file)

  if entry then
    self.current_entry_index = index
    self:goto_entry(entry)
  end
end

function OutputBuffer:parse_filenames()
  local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)

  self.entries = {}
  self.current_entry_index = nil

  for output_line_number, line in ipairs(lines) do
    local matches = self:match_filename(line)
    if matches then
      local filename = matches[2]
      local line_number = tonumber(matches[3]) or 1
      local column_number = tonumber(matches[4]) or 1

      local index = #self.entries + 1

      local absolute_filename = vim.fn.fnamemodify(filename, ":p")
      local file_uri = vim.uri_from_fname(absolute_filename)
      local buf = vim.uri_to_bufnr(file_uri)

      local entry = {
        index = index,
        filename = filename,
        buf = buf,
        line_number = line_number,
        column_number = column_number,
        output_line_number = output_line_number,
        output_line = line,
      }

      if vim.fn.bufloaded(buf) == 1 then
        entry.ext_mark = create_entry_ext_mark(entry)
      end

      self.entries[index] = entry
    end
  end
end

function OutputBuffer:set_entry_signs()
  for i, entry in ipairs(self.entries) do
    vim.api.nvim_buf_set_extmark(self.buf, sign_ns_id, entry.output_line_number - 1, 0, {
      end_col = #entry.output_line,
      line_hl_group = highlight,
      sign_text = "│",
      sign_hl_group = sign_highlight,
    })
  end
end

local function create_colorizer()
  local success, baleia = pcall(require, "baleia")

  if success then
    local b = baleia.setup()

    return function(buf)
      b.once(buf)
    end
  else
    return function()
      -- No colorizer available
    end
  end
end

local colorizer = create_colorizer()

--- @param buf number
local function colorize_output(buf)
  colorizer(buf)
end

--- @return string[]
function OutputBuffer:get_header_lines_with_separator()
  if #self.header_lines == 0 then
    return {}
  end

  local header = vim.deepcopy(self.header_lines)
  header[#header + 1] = ""
  return header
end

function OutputBuffer:parse_filenames_and_set_signs()
  vim.api.nvim_buf_clear_namespace(self.buf, sign_ns_id, 0, -1)
  self:parse_filenames()
  self:set_entry_signs()
end

function OutputBuffer:render_header()
  local header = self:get_header_lines_with_separator()
  if #header == 0 then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, vim.list_extend(header, lines))
end

function OutputBuffer:colorize()
  colorize_output(self.buf)
end

--- @param callback fun()
function OutputBuffer:modify_buffer(callback)
  self.modifying_buffer = true
  local modifiable = vim.bo[self.buf].modifiable
  vim.bo[self.buf].modifiable = true
  callback()
  vim.bo[self.buf].modifiable = modifiable
  vim.bo[self.buf].modified = false
  self.modifying_buffer = false
end

function OutputBuffer:load()
  self:parse_filenames_and_set_signs()

  local render_header = self.profile.render_header
  local colorize = self.profile.colorize

  if self.profile.render_header or self.profile.colorize then
    self:modify_buffer(function()
      if render_header then
        self:render_header()
      end
      if colorize then
        self:colorize()
      end
    end)
  end
end

--- @type OutputBufferOptions
local default_options = {
  profile = nil,
  header_lines = {},
}

local default_profile = {
  file_patterns = {},
  external_file_patterns = {},
  render_header = true,
  colorize = true,
}

--- @param entry runtest.OutputHistoryEntry
function OutputBuffer:get_output_profile_for_entry(entry)
  local output_profile = entry.command_spec.output_profile or entry.command_spec.runner_config.output_profile
  return vim.tbl_deep_extend("force", default_profile, output_profile or {})
end

function OutputBuffer:attach_buffer(buf, options)
  local buffer = self:new(buf, options)
  buffer:load()
  return buffer
end

--- @param buf number
--- @param options OutputBufferOptions
function OutputBuffer:new(buf, options)
  options = vim.tbl_deep_extend("force", default_options, options or {})

  local self = setmetatable({}, OutputBuffer)

  self.buf = buf
  self.profile = vim.tbl_deep_extend("force", default_profile, options.profile or {})

  self.header_lines = options.header_lines
  vim.b[self.buf][output_buffer_marker] = true

  self.entries = {}

  vim.keymap.set("n", "<Enter>", function()
    local current_window = vim.api.nvim_get_current_win()
    local current_line_number = vim.api.nvim_win_get_cursor(current_window)[1]
    local entry = vim.iter(self.entries):find(function(entry)
      return entry.output_line_number == current_line_number
    end)

    if entry then
      self:goto_entry(entry)
    end
  end, { buffer = self.buf })

  vim.api.nvim_create_autocmd("BufReadPost", {
    buffer = self.buf,
    callback = function()
      self:load()
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    buffer = self.buf,
    callback = function()
      if self.modifying_buffer then
        return
      end
      self:parse_filenames_and_set_signs()
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    callback = function(event)
      self:load_buffer_ext_marks(event.buf)
    end,
  })

  self:load()

  return self
end

--- @param buf number
--- @return number | nil
local function find_window_in_current_tab(buf)
  local current_tab = vim.api.nvim_get_current_tabpage()
  local windows = vim.fn.win_findbuf(buf)

  for _, window in ipairs(windows) do
    if vim.api.nvim_win_get_tabpage(window) == current_tab then
      return window
    end
  end
end

--- @param buf number
function OutputBuffer:get_target_window_id(buf)
  local current_window_id = vim.api.nvim_get_current_win()

  if current_window_id == self:current_window() then
    local buffer_window = find_window_in_current_tab(buf)

    if buffer_window then
      return buffer_window
    else
      local last_window = vim.fn.winnr("#")
      return vim.fn.win_getid(last_window)
    end
  else
    return current_window_id
  end
end

function OutputBuffer:current_window()
  return find_window_in_current_tab(self.buf)
end

return OutputBuffer
