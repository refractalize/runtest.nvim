local sql_ts = require("runtest.languages.sql")
local utils = require("runtest.utils")

--- @class M: runtest.RunnerConfig
local M = {
  name = "psql",
  output_profile = {
    file_patterns = {
      "\\v^psql:(\\f+):(\\d+):",
    },
    colorize = false,
    render_header = false,
    always_open = true,
  },
}

local function database_url()
  local url = vim.env.DATABASE_URL
  if type(url) ~= "string" or url == "" then
    error({ message = "DATABASE_URL is not set", level = vim.log.levels.ERROR })
  end
  return url
end

--- @param psql_args string[]
--- @param runner_config runtest.RunnerConfig
--- @param start_config runtest.StartConfig
--- @return runtest.RunSpec
local function run_psql(psql_args, runner_config, start_config)
  local command = utils.build_command_line(
    { "psql", database_url(), "-X", "-v", "ON_ERROR_STOP=1" },
    psql_args,
    runner_config.args,
    start_config.args
  )

  return { command }
end

--- @param runner_config runtest.RunnerConfig
--- @param psql_args string[]
--- @return runtest.CommandSpec
local function psql_command_spec(runner_config, psql_args)
  return {
    runner_config = runner_config,
    run_spec = function(start_config)
      return run_psql(psql_args, runner_config, start_config)
    end,
  }
end

--- @param runner_config runtest.RunnerConfig
--- @return runtest.CommandSpec
function M.line(runner_config)
  local sql_query = sql_ts.current_query()
  return psql_command_spec(runner_config, { "-c", sql_query })
end

--- @param runner_config runtest.RunnerConfig
--- @return runtest.CommandSpec
function M.file(runner_config)
  local filename = vim.fn.expand("%:p")
  if filename == "" then
    error({ message = "No file path for current buffer", level = vim.log.levels.ERROR })
  end

  return psql_command_spec(runner_config, { "-f", filename })
end

return M
