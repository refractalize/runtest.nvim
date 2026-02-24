local namespace_name = "runtest"
local ns_id = vim.api.nvim_create_namespace(namespace_name)
local OutputWindow = require("runtest.output_window")
local OutputLines = require("runtest.output_lines")
local window_layout = require("runtest.window_layout")
local OutputHistory = require("runtest.output_history")
local OutputBuffer = require("runtest.output_buffer")
local buffer_context = require("runtest.buffer_context")

--- @class runtest.StartConfig
--- @field debugger? boolean
--- @field args? string[]

--- @alias runtest.RunSpec [string[], table?, table?]

--- @class runtest.CommandSpec
--- @field debug_spec (fun(start_config: runtest.StartConfig, runner: runtest.Runner): dap.Configuration) | nil
--- @field run_spec (fun(start_config: runtest.StartConfig, runner: runtest.Runner): runtest.RunSpec)
--- @field runner_config runtest.RunnerConfig
--- @field output_profile runtest.OutputProfile?

--- @class runtest.RunnerConfig
--- @field args string[]?
--- @field name string
--- @field env { [string]: string }?
--- @field output_profile runtest.OutputProfile
--- @field commands { [string]: fun(runner_config: runtest.RunnerConfig): runtest.CommandSpec }?
--- @field select_context? fun(runner_config: runtest.RunnerConfig)
--- @field set_context? fun(runner_config: runtest.RunnerConfig, context: string)

--- @alias runtest.OutputWindowShowCondition 'always' | 'on_failure' | 'on_success' | 'never' | function(entry: runtest.OutputHistoryEntry): boolean

--- @class runtest.OutputWindowConfig
--- @field open runtest.OutputWindowShowCondition
--- @field close runtest.OutputWindowShowCondition
--- @field layout runtest.WindowLayout

--- @class runtest.TerminalWindowConfig
--- @field layout runtest.WindowLayout

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
--- @field history runtest.OutputHistoryConfig
--- @field windows { output: runtest.OutputWindowConfig, terminal: runtest.TerminalWindowConfig }
--- @field filetypes { [string]: runtest.RunnerConfig | string }
--- @field runners { [string]: runtest.RunnerConfig }

--- @class runtest.Runner
--- @field output_window OutputWindow | nil
--- @field last_command_spec runtest.CommandSpec | nil
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
    history = {
      max_entries = 10,
    },
    windows = {
      output = {
        open = "on_failure",
        close = "on_success",
        layout = {
          vertical = true,
        },
      },
      terminal = {
        layout = {
          vertical = false,
          size = 0.25,
          min = 10,
          max = 40,
        },
      },
    },
    filetypes = {
      cs = "dotnet",
      ruby = "rails",
      python = "pytest",
      rust = "cargo",
      sql = "psql",
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
      psql = require("runtest.runners.psql"),
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

  local function complete_runner_names(arg_lead)
    local matches = {}
    for runner_name, _ in pairs(self.config.runners or {}) do
      if arg_lead == "" or vim.startswith(runner_name, arg_lead) then
        table.insert(matches, runner_name)
      end
    end
    table.sort(matches)
    return matches
  end

  vim.api.nvim_create_user_command("RunTestAttach", function(args)
    local runner_name = args.args
    self:attach_buffer(vim.api.nvim_get_current_buf(), runner_name)
  end, {
    nargs = 1,
    complete = complete_runner_names,
  })

  vim.api.nvim_create_user_command("RunTestCmd", function(args)
    if #args.fargs < 2 then
      error({
        message = "Usage: RunTestCmd <runner-name> <command> [args...]",
        level = vim.log.levels.WARN,
      })
    end

    local runner_name = args.fargs[1]
    local shell_command = vim.list_slice(args.fargs, 2)
    self:run_command(runner_name, shell_command)
  end, {
    nargs = "+",
    complete = function(arg_lead, cmd_line, cursor_pos)
      local before_cursor = cmd_line:sub(1, cursor_pos)
      local args_input = before_cursor:gsub("^%s*RunTestCmd%s*", "", 1)
      local is_first_arg = args_input == ""
        or (#vim.split(args_input, "%s+", { trimempty = true }) == 1 and not args_input:find("%s"))

      if is_first_arg then
        return complete_runner_names(arg_lead)
      end

      return vim.fn.getcompletion(arg_lead, "shellcmd")
    end,
  })

  M.config = self.config
end

--- @param command_spec runtest.CommandSpec
function Runner:set_last_command_spec(command_spec)
  if self.last_ext_mark ~= nil then
    if self.last_buffer ~= nil and vim.api.nvim_buf_is_valid(self.last_buffer) then
      vim.api.nvim_buf_del_extmark(self.last_buffer, ns_id, self.last_ext_mark)
    end
  end

  self.last_command_spec = command_spec
  self.last_buffer = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  self.last_ext_mark = vim.api.nvim_buf_set_extmark(self.last_buffer, ns_id, cursor[1] - 1, cursor[2], {})
end

local function current_time()
  local seconds, microseconds = vim.uv.gettimeofday()
  return { sec = seconds, usec = microseconds }
end

--- @param command_spec runtest.CommandSpec
--- @param debug_spec dap.Configuration
function Runner:debug(command_spec, debug_spec)
  local dap = require("dap")
  local listen = type(debug_spec) == "table" and debug_spec.request ~= "attach"
  local start_time = current_time()

  local output_lines = OutputLines:new()

  dap.listeners.before["event_exited"][namespace_name] = function(_session, body)
    if listen then
      self:tests_finished({
        output_lines = output_lines:get_lines(),
        exit_code = body.exit_code,
        command_spec = command_spec,
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

function should_open_close(open_close_config, entry)
  if type(open_close_config) == "function" then
    return open_close_config(entry)
  else
    return open_close_config == "always"
      or (open_close_config == "on_failure" and entry.exit_code ~= 0)
      or (open_close_config == "on_success" and entry.exit_code == 0)
  end
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

  local output_profile = entry.command_spec.output_profile or entry.command_spec.runner_config.output_profile
  local output_window_config = output_profile.output_window or self.config.windows.output

  if should_open_close(output_window_config.open, entry) then
    self:open_output_window(output_window_config.layout)
  elseif should_open_close(output_window_config.close, entry) then
    self:close_output_window()
  end
end

--- @param entry runtest.OutputHistoryEntry
function Runner:show_output_history_entry(entry)
  if self.output_window == nil then
    self.output_window = OutputWindow:new_with_output(entry)
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

--- @param buf number
--- @param runner_name string
function Runner:attach_buffer(buf, runner_name)
  local runner_config = lookup_runner_module(self, runner_name)
  local output_profile = runner_config.output_profile
  if self.output_window == nil then
    self.output_window = OutputWindow:new_with_buffer(buf, output_profile)
  else
    self.output_window:set_buffer(buf, output_profile)
  end
end

--- @param runner_name string
--- @param shell_command string[]
function Runner:run_command(runner_name, shell_command)
  local runner_config = lookup_runner_module(self, runner_name)
  local runner_command_spec = {
    runner_config = runner_config,
    output_profile = runner_config.output_profile,
    run_spec = function()
      return { shell_command }
    end,
  }

  self:set_last_command_spec(runner_command_spec)
  self:run_terminal(runner_command_spec, { shell_command })
end

--- @return boolean
function Runner:is_output_window_open()
  if self.output_window == nil then
    return false
  end

  return self.output_window:is_open()
end

--- @param layout runtest.WindowLayout | nil
function Runner:open_output_window(layout)
  if self.output_window == nil then
    vim.notify("No output window available", vim.log.levels.INFO)
    return
  end

  layout = layout or self.config.windows.output.layout

  self.output_window:open(layout)
end

function Runner:close_output_window()
  if self.output_window == nil then
    return
  end

  self.output_window:close()
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

--- @param command_spec runtest.CommandSpec
--- @param run_spec runtest.RunSpec
function Runner:run_terminal(command_spec, run_spec)
  run_spec = parse_job_spec(run_spec)
  local start_time = current_time()
  local output_file = vim.fn.tempname()

  local output_lines = OutputLines:new(function(data)
    return data:gsub("\r$", ""):gsub("\x1b%[%?1h\x1b=", "")
  end)
  local current_window = vim.api.nvim_get_current_win()

  local win = window_layout.new_window(self.config.windows.terminal.layout)
  self.terminal_win = win
  self.terminal_buf = vim.api.nvim_get_current_buf()

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
      command_spec = command_spec,
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

--- @param command_spec runtest.CommandSpec
--- @param job_spec runtest.RunSpec
function Runner:run_job(command_spec, job_spec)
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
      command_spec = command_spec,
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

--- @param layout runtest.WindowLayout | nil
function Runner:open_terminal_window(layout)
  if
    self.terminal_win
    and vim.api.nvim_win_is_valid(self.terminal_win)
    and vim.api.nvim_win_get_buf(self.terminal_win) == self.terminal_buf
  then
    vim.api.nvim_set_current_win(self.terminal_win)
  elseif self.terminal_buf then
    window_layout.open_window(layout or self.config.windows.terminal.layout)
    vim.api.nvim_set_current_buf(self.terminal_buf)
  end
end

--- @param runner_config runtest.RunnerConfig
local function validate_runner_config(runner_config)
  if type(runner_config.name) ~= "string" then
    error({ message = "RunnerConfig.name must be a string", level = vim.log.levels.ERROR })
  end

  if runner_config.commands ~= nil and type(runner_config.commands) ~= "table" then
    error({ message = "RunnerConfig.commands must be a table", level = vim.log.levels.ERROR })
  end
end

--- @return runtest.RunnerConfig[]
function Runner:runner_configs()
  local filetype = vim.bo.filetype
  local configured_runner = self.config.filetypes[filetype]

  if configured_runner == nil then
    error({ message = "No test runner configured for " .. filetype, level = vim.log.levels.WARN })
  end

  if type(configured_runner) == "string" then
    configured_runner = lookup_runner_module(self, configured_runner)
    validate_runner_config(configured_runner)
    return { configured_runner }
  elseif type(configured_runner) == "table" and #configured_runner > 0 then
    local runner_configs = {}
    for _, runner in ipairs(configured_runner) do
      local runner_config = runner
      if type(runner) == "string" then
        runner_config = lookup_runner_module(self, runner)
      end
      validate_runner_config(runner_config)
      table.insert(runner_configs, runner_config)
    end
    return runner_configs
  end

  validate_runner_config(configured_runner)
  return { configured_runner }
end

--- @return runtest.RunnerConfig
function Runner:runner_config()
  local runner_configs = self:runner_configs()
  return runner_configs[1]
end

--- @param command_spec runtest.CommandSpec
--- @param start_config runtest.StartConfig
function Runner:start_command_spec(command_spec, start_config)
  if start_config.debugger then
    if command_spec.debug_spec == nil then
      error({ message = "Command does not support debugging", level = vim.log.levels.ERROR })
    else
      local debug_spec = command_spec.debug_spec(start_config, self)
      self:debug(command_spec, debug_spec)
    end
  else
    local run_spec = command_spec.run_spec(start_config, self)
    self:run_terminal(command_spec, run_spec)
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

--- @param command_spec_name string
--- @return runtest.CommandSpec
function Runner:resolve_command_spec(command_spec_name)
  local runner_configs = self:runner_configs()
  for _, runner_config in ipairs(runner_configs) do
    local commands = runner_config.commands or {}
    local command_fn = commands[command_spec_name]
    if type(command_fn) == "function" then
      return command_fn(runner_config)
    end
  end

  local runner_names = vim
    .iter(runner_configs)
    :map(function(runner_config)
      return runner_config.name
    end)
    :join(", ")
  error({
    message = "No command " .. command_spec_name .. " for runners: " .. runner_names,
    level = vim.log.levels.WARN,
  })
end

--- @param command_spec_name string
--- @param start_config runtest.StartConfig | nil
function Runner:start(command_spec_name, start_config)
  start_config = parse_start_config(start_config)

  local command_spec = self:resolve_command_spec(command_spec_name)

  self:set_last_command_spec(command_spec)

  self:start_command_spec(command_spec, start_config)
end

--- @param command_spec_name string
--- @param start_config runtest.StartConfig | nil
function Runner:get_command(command_spec_name, start_config)
  start_config = parse_start_config(start_config)

  local command_spec = self:resolve_command_spec(command_spec_name)

  return command_spec.run_spec(start_config, self)
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
  if self.last_command_spec == nil then
    error({ message = "No last command", level = vim.log.levels.INFO })
  end

  self:start_command_spec(self.last_command_spec, parse_start_config(start_config))
end

function Runner:goto_last()
  if self.last_command_spec == nil then
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

--- @param layout runtest.WindowLayout | nil
function M.open_output(layout)
  runner:open_output_window(layout)
end

--- @param layout runtest.WindowLayout | nil
function M.open_terminal(layout)
  runner:open_terminal_window(layout)
end

function M.run(command_spec_name, start_config)
  error_wrapper(function()
    runner:start(command_spec_name, start_config)
  end)
end

function M.get_command(command_spec_name, start_config)
  return error_wrapper(function()
    return runner:get_command(command_spec_name, start_config)
  end)
end

function M.debug(command_spec_name, start_config)
  error_wrapper(function()
    runner:start(command_spec_name, vim.tbl_extend("force", start_config or {}, { debugger = true }))
  end)
end

function M.select_context()
  error_wrapper(function()
    local runner_config = runner:runner_config()
    local select_context = runner_config.select_context

    if type(select_context) ~= "function" then
      error({ message = "Current runner does not support context selection", level = vim.log.levels.WARN })
    end

    select_context(runner_config)
  end)
end

--- @param context string
function M.set_context(context)
  error_wrapper(function()
    buffer_context.set_buffer_context(0, context)
  end)
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

--- @return runtest.CommandSpec | nil
function M.last_command_spec()
  return runner.last_command_spec
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

function M.attach_buffer(buf, runner_name)
  error_wrapper(function()
    runner:attach_buffer(buf, runner_name)
  end)
end

return M
