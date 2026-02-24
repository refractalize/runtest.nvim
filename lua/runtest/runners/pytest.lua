local python_ts = require("runtest.languages.python")
local utils = require("runtest.utils")

--- @class M: runtest.RunnerConfig
local M = {}

M.output_profile = {
  file_patterns = {
    '\\vFile "(\\f+)",\\s*line\\s*(\\d+),',
    "\\v^(\\f+):(\\d+)",
  },
}

M.name = "pytest"

--- @param runner_config runtest.RunnerConfig
--- @param args string[]
--- @param start_config runtest.StartConfig
local function pytest_args(runner_config, args, start_config)
  return utils.build_command_line(args, runner_config.args, start_config.args)
end

local function run_pytest(runner_config, args, start_config)
  return {
    utils.build_command_line(
      { "python", "-m", "pytest" },
      { "--color=yes" },
      pytest_args(runner_config, args, start_config)
    ),
  }
end

local function debug_pytest(runner_config, args, start_config)
  return {
    name = "Debug Pytest",
    type = "python",
    request = "launch",
    module = "pytest",
    args = pytest_args(runner_config, args, start_config),
  }
end

--- @param runner_config runtest.RunnerConfig
--- @param args string[]
--- @returns runtest.CommandSpec
local function pytest_profile(runner_config, args)
  return {
    runner_config = runner_config,
    debug_spec = function(start_config)
      return debug_pytest(runner_config, args, start_config)
    end,
    run_spec = function(start_config)
      return run_pytest(runner_config, args, start_config)
    end,
  }
end

--- @param runner_config runtest.RunnerConfig
--- @returns runtest.CommandSpec
function M.line(runner_config)
  local filename = vim.fn.expand("%:p")
  local test_pattern = vim.list_extend({ filename }, python_ts.test_path())
  local args = { vim.fn.join(test_pattern, "::") }

  return pytest_profile(runner_config, args)
end

--- @param runner_config runtest.RunnerConfig
--- @returns runtest.CommandSpec
function M.all(runner_config)
  return pytest_profile(runner_config, {})
end

--- @param runner_config runtest.RunnerConfig
--- @returns runtest.CommandSpec
function M.file(runner_config)
  local filename = vim.fn.expand("%:p")
  local args = { filename }

  return pytest_profile(runner_config, args)
end

--- @param runner_config runtest.RunnerConfig
--- @returns runtest.CommandSpec
function M.project(runner_config)
  local project_root = vim.fs.root(0, { "pyproject.toml", "setup.py", ".git" })
  local args = { project_root }

  return pytest_profile(runner_config, args)
end

return M
