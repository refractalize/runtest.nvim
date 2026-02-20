local namespace_name = "runtest"
local ns_id = vim.api.nvim_create_namespace(namespace_name)
local OutputWindow = require("runtest.output_window")
local OutputLines = require("runtest.output_lines")
local window_layout = require("runtest.window_layout")
local OutputHistory = require("runtest.output_history")
local OutputBuffer = require("runtest.output_buffer")

--- @class runtest.StartConfig
--- @field debugger? boolean
--- @field args? string[]

--- @alias runtest.RunSpec [string[], table?, table?]

--- @class runtest.Profile
--- @field debug_spec (fun(start_config: runtest.StartConfig, runner: runtest.Runner): dap.Configuration)
--- @field run_spec (fun(start_config: runtest.StartConfig, runner: runtest.Runner): runtest.RunSpec)
--- @field runner_config runtest.RunnerConfig
--- @field output_profile runtest.OutputProfile?

--- @class runtest.RunnerConfig
--- @field args string[]?
--- @field name string
--- @field env { [string]: string }?
--- @field output_profile runtest.OutputProfile
--- @field line_tests fun(): runtest.Profile
--- @field all_tests fun(): runtest.Profile
--- @field file_tests fun(): runtest.Profile

local exec_no_tty = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "exec-no-tty"

local M = {}

local function handle_error(err)
  if type(err) == "table" and type(err.message) == "string" then
    vim.notify(err.message, err.level or vim.log.levels.ERROR)
  else
    vim.notify("Error: " .. err, vim.log.levels.ERROR)
    error(err)
  end
end

--- @class runtest.Config
--- @field open_output_on_failure boolean
--- @field close_output_on_success boolean
--- @field history runtest.OutputHistoryConfig
--- @field windows { output: runtest.WindowProfile, terminal: runtest.WindowProfile }
--- @field filetypes { [string]: runtest.RunnerConfig | string }
--- @field runners { [string]: runtest.RunnerConfig }

--- @class runtest.Runner
--- @field output_window OutputWindow | nil
--- @field last_profile runtest.Profile | nil
--- @field last_buffer number | nil
--- @field last_ext_mark number | nil
--- @field terminal_buf number | nil
--- @field config runtest.Config
--- @field output_history runtest.OutputHistory
local Runner = {}
Runner.__index = Runner

function Runner.new()
  local self = setmetatable({}, Runner)
  self.output_window = nil
  self.config = {
    open_output_on_failure = false,
    close_output_on_success = false,
    history = {
      max_entries = 10,
    },
    windows = {
      output = {
        vertical = true,
      },
      terminal = {
        vertical = false,
        size = 0.25,
        min = 10,
        max = 40,
      },
    },
    filetypes = {
      cs = "dotnet",
      ruby = "rails",
      python = "pytest",
      rust = "cargo",
      typescriptreact = "jest",
      typescript = "jest",
      javascriptreact = "jest",
      javascript = "jest",
    },
    runners = {
      dotnet = require("runtest.runners.dotnet"),
      rails = require("runtest.runners.rails"),
      pytest = require("runtest.runners.pytest"),
      cargo = require("runtest.runners.cargo"),
      jest = require("runtest.runners.jest"),
      vitest = require("runtest.runners.vitest"),
    },
  }
  self.output_history = OutputHistory:new()
  return self
end

function Runner:setup(config)
  self.config = vim.tbl_deep_extend("force", self.config, config)
  self.output_history:setup(config.history)

  vim.api.nvim_create_user_command("RunTestAttach", function(args)
    local profile_name = args.args
    self:attach_buffer(vim.api.nvim_get_current_buf(), profile_name)
  end, {
    nargs = 1,
    complete = function(arg_lead)
      local matches = {}
      for runner_name, _ in pairs(self.config.runners or {}) do
        if arg_lead == "" or vim.startswith(runner_name, arg_lead) then
          table.insert(matches, runner_name)
        end
      end
      table.sort(matches)
      return matches
    end,
  })

  M.config = self.config
end

--- @param profile runtest.Profile
function Runner:set_last_profile(profile)
  if self.last_ext_mark ~= nil then
    if self.last_buffer ~= nil and vim.api.nvim_buf_is_valid(self.last_buffer) then
      vim.api.nvim_buf_del_extmark(self.last_buffer, ns_id, self.last_ext_mark)
    end
  end

  self.last_profile = profile
  self.last_buffer = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  self.last_ext_mark = vim.api.nvim_buf_set_extmark(self.last_buffer, ns_id, cursor[1] - 1, cursor[2], {})
end

local function current_time()
  local seconds, microseconds = vim.uv.gettimeofday()
  return { sec = seconds, usec = microseconds }
end

--- @param profile runtest.Profile
--- @param debug_spec dap.Configuration
function Runner:debug(profile, debug_spec)
  local dap = require("dap")
  local listen = type(debug_spec) == "table" and debug_spec.request ~= "attach"
  local start_time = current_time()

  local output_lines = OutputLines:new()

  dap.listeners.before["event_exited"][namespace_name] = function(_session, body)
    if listen then
      self:tests_finished({
        output_lines = output_lines:get_lines(),
        exit_code = body.exit_code,
        profile = profile,
        start_time = start_time,
        end_time = current_time(),
        debug_spec = debug_spec,
      })
    end
  end

  dap.listeners.before["event_output"][namespace_name] = function(_session, body)
    if listen then
      if body.category == "stdout" or body.category == "stderr" then
        output_lines:append(vim.fn.split(body.output, "\n", true))
      end
    end
  end

  dap.run(debug_spec)
end

--- @param entry runtest.OutputHistoryEntry
function Runner:tests_finished(entry)
  local failed = entry.exit_code ~= 0
  if failed then
    vim.notify("Tests failed", vim.log.levels.ERROR)
  else
    vim.notify("Tests passed", vim.log.levels.INFO)
  end

  self.output_history:add_entry(entry)
  self:show_output_history_entry(entry)

  if failed and self.config.open_output_on_failure then
    self:open_output_window()
  end

  if not failed and self.config.close_output_on_success then
    if self.output_window then
      self.output_window:close()
    end
  end
end

--- @param entry runtest.OutputHistoryEntry
function Runner:show_output_history_entry(entry)
  if self.output_window == nil then
    self.output_window = OutputWindow:new_with_output()
  else
    self.output_window:set_entry(entry)
  end
end

function Runner:next_output_history()
  local entry = self.output_history:next_entry()

  if entry == nil then
    return
  end

  self:show_output_history_entry(entry)
end

function Runner:previous_output_history()
  local entry = self.output_history:previous_entry()

  if entry == nil then
    return
  end

  self:show_output_history_entry(entry)
end

--- @param self runtest.Runner
--- @param runner_name string
--- @return runtest.RunnerConfig
local function lookup_runner_module(self, runner_name)
  local runner_module = self.config.runners[runner_name]
  if not runner_module then
    error({ message = "No runner module for " .. runner_name, level = vim.log.levels.ERROR })
  end
  return runner_module
end

function Runner:attach_buffer(buf, profile_name)
  local runner_config = lookup_runner_module(self, profile_name)
  local output_profile = runner_config.output_profile
  if self.output_window == nil then
    self.output_window = OutputWindow:new_with_buffer(buf, output_profile)
  else
    self.output_window:set_buffer(buf, output_profile)
  end
end

--- @param new_window_command string|nil The VIM command to run to create the window, default's to `vsplit`
function Runner:open_output_window(new_window_command)
  if self.output_window == nil then
    vim.notify("No output window available", vim.log.levels.INFO)
    return
  end

  self.output_window:open(new_window_command or "vsplit")
end

--- @param job_spec runtest.RunSpec
local function parse_job_spec(job_spec)
  if type(job_spec) ~= "table" then
    error("expected run_spec to be a table, got " .. type(job_spec))
  end

  if type(job_spec[1]) ~= "table" then
    error("expected run_spec[1] to be a table, got " .. type(job_spec[1]))
  end

  if vim.iter(job_spec[1]):any(function(arg)
    return type(arg) ~= "string"
  end) then
    error("expected run_spec[1] to be a list of strings")
  end

  return job_spec
end

local function follow_latest_output()
  vim.cmd.normal("G")
end

--- @param profile runtest.Profile
--- @param run_spec runtest.RunSpec
function Runner:run_terminal(profile, run_spec)
  run_spec = parse_job_spec(run_spec)
  local start_time = current_time()
  local output_file = vim.fn.tempname()

  local output_lines = OutputLines:new(function(data)
    return data:gsub("\r$", ""):gsub("\x1b%[%?1h\x1b=", "")
  end)
  local current_window = vim.api.nvim_get_current_win()

  local win, buf = window_layout.new_window(self.config.windows.terminal)
  self.terminal_win = win
  self.terminal_buf = buf

  local function on_data(_, data)
    output_lines:append(data)
  end

  local on_exit = function(_, exit_code)
    if vim.api.nvim_buf_is_valid(self.terminal_buf) then
      vim.api.nvim_buf_delete(self.terminal_buf, { force = true })
    end
    self.terminal_buf = nil
    self.terminal_win = nil

    self:tests_finished({
      output_file = output_file,
      output_lines = output_lines:get_lines(),
      exit_code = exit_code,
      profile = profile,
      start_time = start_time,
      end_time = current_time(),
      run_spec = run_spec,
    })
  end

  local options = vim.tbl_extend("keep", run_spec[3] or {}, {
    tty = true,
  })
  local command = options.tty and vim.list_extend({ exec_no_tty, output_file }, run_spec[1]) or run_spec[1]

  vim.fn.jobstart(
    command,
    vim.tbl_extend("force", run_spec[2] or {}, {
      on_exit = on_exit,
      stdout_buffered = true,
      on_stdout = on_data,
      term = true,
    })
  )

  follow_latest_output()

  vim.api.nvim_set_current_win(current_window)
end

local function combine(fn1, fn2)
  return function(...)
    fn1(...)
    fn2(...)
  end
end

local function optional_combine(fn1, fn2)
  if fn2 == nil then
    return fn1
  else
    return combine(fn1, fn2)
  end
end

--- @param profile runtest.Profile
--- @param job_spec runtest.RunSpec
function Runner:run_job(profile, job_spec)
  job_spec = parse_job_spec(job_spec)
  local start_time = current_time()
  local output_file = vim.fn.tempname()

  local output_lines = OutputLines:new(function(data)
    return data:gsub("\r$", "")
  end)

  local function on_data(_, data)
    output_lines:append(data)
  end

  local on_exit = function(_, exit_code)
    self:tests_finished({
      output_file = output_file,
      output_lines = output_lines:get_lines(),
      exit_code = exit_code,
      profile = profile,
      start_time = start_time,
      end_time = current_time(),
      job_spec = job_spec,
    })
  end

  local no_tty_command = vim.list_extend({ exec_no_tty, output_file }, job_spec[1])

  local job_spec_options = job_spec[2] or {}

  local options = vim.tbl_extend("force", job_spec_options, {
    on_exit = optional_combine(on_exit, job_spec_options.on_exit),
    on_stdout = optional_combine(on_data, job_spec_options.on_stdout),
    on_stderr = optional_combine(on_data, job_spec_options.on_stderr),
  })

  vim.fn.jobstart(no_tty_command, options)
end

--- @param new_window_command string
function Runner:open_terminal_window(new_window_command)
  if
    self.terminal_win
    and vim.api.nvim_win_is_valid(self.terminal_win)
    and vim.api.nvim_win_get_buf(self.terminal_win) == self.terminal_buf
  then
    vim.api.nvim_set_current_win(self.terminal_win)
  elseif self.terminal_buf then
    vim.cmd(new_window_command)
    vim.api.nvim_set_current_buf(self.terminal_buf)
  end
end

--- @param runner_config runtest.RunnerConfig
local function validate_runner_config(runner_config)
  if type(runner_config.name) ~= "string" then
    error({ message = "RunnerConfig.name must be a string", level = vim.log.levels.ERROR })
  end
end

--- @return runtest.RunnerConfig
function Runner:runner_config()
  local filetype = vim.bo.filetype
  local runner_config = self.config.filetypes[filetype]

  if runner_config == nil then
    error({ message = "No test runner configured for " .. filetype, level = vim.log.levels.WARN })
  end

  if type(runner_config) == "string" then
    runner_config = lookup_runner_module(self, runner_config)
  elseif type(runner_config) == "table" and #runner_config > 0 then
    local merged_config = {}
    for _, runner_name in ipairs(runner_config) do
      local runner_module = lookup_runner_module(self, runner_name)
      merged_config = vim.tbl_extend("force", runner_module, merged_config)
    end
    runner_config = merged_config
  end

  validate_runner_config(runner_config)

  return runner_config
end

--- @param profile runtest.Profile
--- @param start_config runtest.StartConfig
function Runner:start_profile(profile, start_config)
  if start_config.debugger then
    local debug_spec = profile.debug_spec(start_config, self)
    self:debug(profile, debug_spec)
  else
    local run_spec = profile.run_spec(start_config, self)
    self:run_terminal(profile, run_spec)
  end
end

--- @param start_config runtest.StartConfig | nil
--- @return runtest.StartConfig
local function parse_start_config(start_config)
  return vim.tbl_extend("force", {
    debugger = false,
    args = {},
  }, start_config or {})
end

--- @param profile_name string
--- @return runtest.Profile
function Runner:resolve_profile(profile_name)
  local runner_config = self:runner_config()

  local profile_fn = runner_config[profile_name]

  if not profile_fn then
    error({
      message = "No profile " .. profile_name .. " for runner " .. runner_config.name,
      level = vim.log.levels.WARN,
    })
  end

  return profile_fn(runner_config)
end

--- @param profile_name string
--- @param start_config runtest.StartConfig | nil
function Runner:start_profile_name(profile_name, start_config)
  start_config = parse_start_config(start_config)

  local profile = self:resolve_profile(profile_name)

  self:set_last_profile(profile)

  self:start_profile(profile, start_config)
end

--- @param profile_name string
--- @param start_config runtest.StartConfig | nil
function Runner:get_profile_command(profile_name, start_config)
  start_config = parse_start_config(start_config)

  local profile = self:resolve_profile(profile_name)

  return profile.run_spec(start_config, self)
end

--- @param start_config runtest.StartConfig | nil
function Runner:debug_last(start_config)
  if start_config then
    start_config.debugger = true
  else
    start_config = { debugger = true }
  end

  self:run_last(start_config)
end

--- @param start_config runtest.StartConfig | nil
function Runner:run_last(start_config)
  if self.last_profile == nil then
    error({ message = "No last test", level = vim.log.levels.INFO })
  end

  self:start_profile(self.last_profile, parse_start_config(start_config))
end

function Runner:goto_last()
  if self.last_profile == nil then
    error({ message = "No last test", level = vim.log.levels.INFO })
  end

  vim.api.nvim_set_current_buf(self.last_buffer)
  local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(self.last_buffer, ns_id, self.last_ext_mark, {})
  vim.api.nvim_win_set_cursor(0, { extmark_pos[1] + 1, extmark_pos[2] })
end

local runner = Runner.new()
M.runner = runner

--- @generic T
--- @param fn fun(): T?
--- @return T?
local function error_wrapper(fn)
  local status, result = xpcall(function()
    return fn()
  end, function(err)
    return debug.traceback(err, 2)
  end)

  if not status then
    handle_error(result)
  else
    return result
  end
end

function M.setup(config)
  runner:setup(config)
end

--- @param new_window_command string|nil The VIM command to run to create the window, default's to `vsplit`
function M.open_output(new_window_command)
  runner:open_output_window(new_window_command)
end

--- @param new_window_command string|nil The VIM command to run to create the window, default's to `split`
function M.open_terminal(new_window_command)
  runner:open_terminal_window(new_window_command or "split")
end

for _, profile_name in ipairs({ "line_tests", "all_tests", "file_tests", "lint", "build" }) do
  M["run_" .. profile_name] = function(start_config)
    error_wrapper(function()
      runner:start_profile_name(profile_name, start_config)
    end)
  end
  M["get_" .. profile_name .. "_command"] = function(start_config)
    return error_wrapper(function()
      return runner:get_profile_command(profile_name, start_config)
    end)
  end
end

for _, profile_name in ipairs({ "line_tests", "all_tests", "file_tests" }) do
  M["debug_" .. profile_name] = function(start_config)
    error_wrapper(function()
      runner:start_profile_name(profile_name, vim.tbl_extend("force", start_config or {}, { debugger = true }))
    end)
  end
end

function M.run_last(start_config)
  error_wrapper(function()
    runner:run_last(start_config)
  end)
end

function M.debug_last(start_config)
  error_wrapper(function()
    runner:debug_last(start_config)
  end)
end

function M.goto_last()
  error_wrapper(function()
    runner:goto_last()
  end)
end

--- @return runtest.Profile | nil
function M.last_profile()
  return runner.last_profile
end

function M.goto_next_entry(allow_external_file)
  allow_external_file = allow_external_file == nil and true or allow_external_file
  error_wrapper(function()
    if runner.output_window then
      runner.output_window.output_buffer:goto_next_entry(allow_external_file)
    end
  end)
end

function M.goto_previous_entry(allow_external_file)
  allow_external_file = allow_external_file == nil and true or allow_external_file
  error_wrapper(function()
    if runner.output_window then
      runner.output_window.output_buffer:goto_previous_entry(allow_external_file)
    end
  end)
end

function M.send_entries_to_quickfix()
  error_wrapper(function()
    if not runner.output_window then
      return
    end

    local entries = runner.output_window.output_buffer.entries
    local quickfix_entries = vim
      .iter(entries)
      :map(function(entry)
        return {
          filename = entry.filename,
          lnum = entry.line_number,
          col = entry.column_number,
          text = entry.output_line,
        }
      end)
      :totable()
    vim.fn.setqflist(quickfix_entries, "r")
  end)
end

function M.send_entries_to_fzf()
  error_wrapper(function()
    local fzf_lua = require("fzf-lua")
    if not runner.output_window then
      return
    end

    local entries = runner.output_window.output_buffer.entries
    local fzf_entries = vim
      .iter(entries)
      :map(function(entry)
        return entry.filename .. ":" .. entry.line_number .. ":" .. entry.column_number
      end)
      :totable()
    fzf_lua.fzf_exec(fzf_entries, {
      fzf_opts = {
        ["--no-sort"] = "",
      },
      fn_transform = function(x)
        return fzf_lua.make_entry.file(x, { file_icons = true, color_icons = true })
      end,
      actions = fzf_lua.config.globals.actions.files,
      previewer = "builtin",
    })
  end)
end

function M.next_output_history()
  error_wrapper(function()
    runner:next_output_history()
  end)
end

function M.previous_output_history()
  error_wrapper(function()
    runner:previous_output_history()
  end)
end

function M.execute_command(command)
  error_wrapper(function()
    vim.cmd(command)
  end)
end

function M.attach_buffer(buf, profile_name)
  error_wrapper(function()
    runner:attach_buffer(buf, profile_name)
  end)
end

return M
