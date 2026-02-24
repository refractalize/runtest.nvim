local OutputBuffer = require("runtest.output_buffer")
local window_layout = require("runtest.window_layout")

--- @class OutputWindow
--- @field output_buffer runtest.OutputBuffer
local OutputWindow = {}
OutputWindow.__index = OutputWindow

--- @param job_spec runtest.RunSpec
--- @returns string[]
local function render_command_line(job_spec)
  local env = (job_spec[2] or {}).env
  local env_str = env
    and vim.fn.join(
      vim.tbl_map(function(key)
        return key .. "=" .. vim.fn.shellescape(env[key])
      end, vim.tbl_keys(env)),
      " "
    )
  local command_str = vim.fn.join(vim.tbl_map(function(arg)
    return vim.fn.shellescape(arg)
  end, job_spec[1]))

  return {
    "Command: " .. (env_str and env_str .. " " .. command_str or command_str),
  }
end

local function time_diff_in_microseconds(start_time, end_time)
  local sec_diff = end_time.sec - start_time.sec
  local usec_diff = end_time.usec - start_time.usec
  return sec_diff * 1000000 + usec_diff
end

local function render_entry_timing(entry)
  local start_seconds = entry.start_time.sec
  local end_seconds = entry.end_time.sec
  local start_time = os.date("%Y-%m-%d %H:%M:%S", start_seconds)
  local end_time = os.date("%Y-%m-%d %H:%M:%S", end_seconds)
  local duration_ms = math.floor(time_diff_in_microseconds(entry.start_time, entry.end_time) / 1000)
  return {
    "Start time: " .. start_time,
    "End time: " .. end_time,
    "Duration: " .. duration_ms .. "ms",
  }
end

--- @param run_entry runtest.OutputHistoryEntry
--- @return string[]
local function render_output_header_lines(run_entry)
  local detail_lines = run_entry.run_spec and render_command_line(run_entry.run_spec) or {}
  local timing = render_entry_timing(run_entry)
  return vim.list_extend(detail_lines, timing)
end

--- @param run_entry runtest.OutputHistoryEntry
--- @return number
local function create_buffer_for_output(run_entry, filetype)
  if run_entry.output_file then
    local output_file_uri = vim.uri_from_fname(vim.fn.fnamemodify(run_entry.output_file, ":p"))
    local buf = vim.uri_to_bufnr(output_file_uri)
    vim.fn.bufload(buf)
    vim.bo[buf].buflisted = false
    vim.bo[buf].buftype = "acwrite"
    vim.bo[buf].modifiable = false

    if filetype then
      vim.bo[buf].filetype = filetype
    end

    return buf
  elseif run_entry.output_lines then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, run_entry.output_lines)
    vim.bo[buf].bufhidden = "unload"

    vim.bo[buf].buftype = "acwrite"
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false

    if filetype then
      vim.bo[buf].filetype = filetype
    end

    return buf
  else
    error("Invalid run entry: missing output")
  end
end

--- @param run_entry runtest.OutputHistoryEntry
function OutputWindow:set_entry(run_entry)
  local output_profile = OutputBuffer:get_output_profile_for_entry(run_entry)
  local header_lines = render_output_header_lines(run_entry)
  local output_buffer = run_entry.output_buffer

  if not (output_buffer and vim.api.nvim_buf_is_valid(output_buffer.buf)) then
    local buf = create_buffer_for_output(run_entry, output_profile.filetype)
    output_buffer = OutputBuffer:new(buf, { profile = output_profile, header_lines = header_lines })
    run_entry.output_buffer = output_buffer
  end

  self.output_buffer = output_buffer
end

--- @param buf number
--- @param profile runtest.OutputProfile
function OutputWindow:set_buffer(buf, profile)
  self.output_buffer = OutputBuffer:new(buf, { profile = profile })
end

--- @param run_entry runtest.OutputHistoryEntry
function OutputWindow:new_with_output(run_entry)
  local self = setmetatable({}, OutputWindow)
  self:set_entry(run_entry)
  return self
end

--- @param buf number
--- @param profile runtest.OutputProfile
function OutputWindow:new_with_buffer(buf, profile)
  local self = setmetatable({}, OutputWindow)
  self:set_buffer(buf, profile)
  return self
end

--- @return number | nil
local function find_output_window_in_current_tab()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local windows = vim.api.nvim_tabpage_list_wins(current_tab)

  for _, win in ipairs(windows) do
    local buf = vim.api.nvim_win_get_buf(win)
    if OutputBuffer.is_output_buffer(buf) then
      return win
    end
  end
end

function OutputWindow:is_open()
  return find_output_window_in_current_tab() ~= nil
end

--- @param layout runtest.WindowLayout | nil
function OutputWindow:open(layout)
  local current_window = find_output_window_in_current_tab()

  if current_window then
    vim.api.nvim_set_current_win(current_window)
    local current_buf = vim.api.nvim_win_get_buf(current_window)
    if current_buf ~= self.output_buffer.buf then
      vim.api.nvim_win_set_buf(current_window, self.output_buffer.buf)
    end
  else
    window_layout.new_window(layout)
    vim.api.nvim_set_current_buf(self.output_buffer.buf)
  end
end

function OutputWindow:close()
  local current_window = find_output_window_in_current_tab()

  if current_window then
    vim.api.nvim_win_close(current_window, true)
  end
end

return OutputWindow
