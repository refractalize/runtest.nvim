local sql_ts = require("runtest.languages.sql")
local utils = require("runtest.utils")
local buffer_context = require("runtest.buffer_context")

--- @class M: runtest.RunnerConfig
local M = {
  name = "psql",
  output_profile = {
    file_patterns = {},
    colorize = false,
    render_header = false,
    output_window = {
      open = "always",
    },
  },
  default_context_env_var = "DATABASE_URL",
  context_env_var_pattern = "*_DATABASE_URL",
  database_runners = {},
  commands = {},
  codelens = {},
}

--- @class runtest.psql.CommandContext
--- @field kind "line" | "file" | "visual"
--- @field bufnr integer
--- @field line_number? integer
--- @field filename? string
--- @field query_text? string

--- @param database_url string
--- @return string
local function database_url_scheme(database_url)
  local scheme = database_url:match("^([%a][%w+.-]*)://")
  if scheme == nil then
    error({
      message = "Database URL must include a protocol: " .. database_url,
      level = vim.log.levels.ERROR,
    })
  end

  return scheme:lower()
end

--- @param database_url string
--- @param command_context runtest.psql.CommandContext
--- @param runner_config runtest.RunnerConfig
--- @param start_config runtest.StartConfig
--- @return runtest.RunSpec
local function run_postgres(database_url, command_context, runner_config, start_config)
  local psql_args

  if command_context.kind == "line" then
    local line_number = command_context.line_number
    local bufnr = command_context.bufnr
    if type(line_number) ~= "number" or line_number <= 0 then
      error({ message = "No line number captured for SQL line run", level = vim.log.levels.ERROR })
    end

    psql_args = { "-c", sql_ts.current_query(bufnr, line_number) }
  elseif command_context.kind == "file" then
    local filename = command_context.filename
    if type(filename) ~= "string" or filename == "" then
      error({ message = "No file path captured for SQL file run", level = vim.log.levels.ERROR })
    end

    psql_args = { "-f", filename }
  elseif command_context.kind == "visual" then
    local query_text = command_context.query_text
    if type(query_text) ~= "string" or query_text == "" then
      error({ message = "No visual selection captured for SQL run", level = vim.log.levels.ERROR })
    end

    psql_args = { "-c", query_text }
  else
    error({ message = "Unsupported SQL command context: " .. tostring(command_context.kind), level = vim.log.levels.ERROR })
  end

  local command = utils.build_command_line(
    { "psql", database_url, "-X", "-v", "ON_ERROR_STOP=1" },
    psql_args,
    runner_config.args,
    start_config.args
  )

  return { command }
end

M.database_runners = {
  postgres = run_postgres,
  postgresql = run_postgres,
}

--- @param runner_config runtest.RunnerConfig
--- @param command_context runtest.psql.CommandContext
--- @return runtest.CommandSpec
local function psql_command_spec(runner_config, command_context)
  return {
    runner_config = runner_config,
    run_spec = function(start_config)
      local database_url = buffer_context.get_buffer_context(command_context.bufnr, runner_config)
      local scheme = database_url_scheme(database_url)
      local database_runner = runner_config.database_runners[scheme]

      if database_runner == nil then
        error({
          message = "Unsupported database protocol for SQL runner: " .. scheme,
          level = vim.log.levels.ERROR,
        })
      end

      return database_runner(database_url, command_context, runner_config, start_config)
    end,
  }
end

--- @param runner_config runtest.RunnerConfig
--- @return runtest.CommandSpec
function M.commands.line(runner_config)
  local bufnr = vim.api.nvim_get_current_buf()
  local line_number = vim.api.nvim_win_get_cursor(0)[1]
  return psql_command_spec(runner_config, {
    kind = "line",
    bufnr = bufnr,
    line_number = line_number,
  })
end

--- @param runner_config runtest.RunnerConfig
--- @return runtest.CommandSpec
function M.commands.file(runner_config)
  local bufnr = vim.api.nvim_get_current_buf()
  local filename = vim.fn.expand("%:p")
  if filename == "" then
    error({ message = "No file path for current buffer", level = vim.log.levels.ERROR })
  end

  return psql_command_spec(runner_config, {
    kind = "file",
    bufnr = bufnr,
    filename = filename,
  })
end

--- @param runner_config runtest.RunnerConfig
--- @return runtest.CommandSpec
function M.commands.visual(runner_config)
  local bufnr = vim.api.nvim_get_current_buf()
  local sql_query = utils.get_visual_text()
  if sql_query == nil then
    error({ message = "No visual selection", level = vim.log.levels.ERROR })
  end

  return psql_command_spec(runner_config, {
    kind = "visual",
    bufnr = bufnr,
    query_text = sql_query,
  })
end

function M.codelens.get_lines(runner_config)
  local query_lines = sql_ts.get_query_lines()
  return vim.tbl_map(function(line)
    return { line = line }
  end, query_lines)
end

return M
