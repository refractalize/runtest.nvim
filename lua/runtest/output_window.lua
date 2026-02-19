local OutputBuffer = require("runtest.output_buffer")

--- @class OutputWindow
--- @field buf number
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
function OutputWindow:set_entry(run_entry)
  local detail_lines = run_entry.run_spec and render_command_line(run_entry.run_spec) or {}
  local timing = render_entry_timing(run_entry)
  local lines = vim.list_extend(vim.list_extend(vim.list_extend(detail_lines, timing), { "" }), run_entry.output_lines)
  vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf })
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf })

  local output_profile = run_entry.profile.output_profile or run_entry.profile.runner_config.output_profile

  self.output_buffer.profile = output_profile
  self.output_buffer:load()
end

function OutputWindow:new()
  local self = setmetatable({}, OutputWindow)
  self.buf = vim.uri_to_bufnr("runtest://output")
  self.output_buffer = OutputBuffer:new(self.buf, { allow_read = false })
  return self
end

--- @param new_window_command string
function OutputWindow:open(new_window_command)
  local current_window = self.output_buffer:current_window()

  if current_window then
    vim.api.nvim_set_current_win(current_window)
  else
    vim.cmd(new_window_command)
    vim.api.nvim_set_current_buf(self.buf)
  end
end

function OutputWindow:close()
  local current_window = self.output_buffer:current_window()

  if current_window then
    vim.api.nvim_win_close(current_window, true)
  end
end

return OutputWindow
