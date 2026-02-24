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
  database_env_var = "DATABASE_URL",
  database_env_var_filter = "DATABASE_URL_*",
  commands = {},
}

--- @param runner_config runtest.RunnerConfig
--- @return string
local function get_default_database_env_var(runner_config)
  return runner_config.database_env_var or "DATABASE_URL"
end

--- @param runner_config runtest.RunnerConfig
--- @param env_var_name string
--- @return boolean
local function env_var_matches_filter(runner_config, env_var_name)
  local database_env_var_filter = runner_config.database_env_var_filter
  if type(database_env_var_filter) == "string" then
    local pattern = vim.fn.glob2regpat(database_env_var_filter)
    return vim.fn.match(env_var_name, pattern) ~= -1
  elseif type(database_env_var_filter) == "function" then
    local ok, result = pcall(database_env_var_filter, env_var_name)
    return ok and result == true
  else
    return false
  end
end

function resolve_database_url_var(database_env_var)
  if type(database_env_var) ~= "string" or database_env_var == "" then
    error({
      message = "Database URL environment variable must be a non-empty string: " .. database_env_var,
      level = vim.log.levels.ERROR,
    })
  end

  local env_url = vim.env[database_env_var]
  if type(env_url) ~= "string" or env_url == "" then
    error({
      message = "Database URL environment variable is empty or missing: " .. database_env_var,
      level = vim.log.levels.ERROR,
    })
  end

  return env_url
end

function resolve_database_url(runner_config)
  local bufnr = vim.api.nvim_get_current_buf()
  local context = buffer_context.get_buffer_context(bufnr)
  if type(context) == "string" and context ~= "" then
    return resolve_database_url_var(context)
  end

  local default_database_env_var = get_default_database_env_var(runner_config)
  return resolve_database_url_var(default_database_env_var)
end

function get_database_url_env_vars(runner_config)
  local env_vars = {}
  local database_env_var = get_default_database_env_var(runner_config)

  for key, _ in pairs(vim.fn.environ()) do
    if key == database_env_var or env_var_matches_filter(runner_config, key) then
      table.insert(env_vars, key)
    end
  end

  table.sort(env_vars)

  return env_vars
end

--- @param psql_args string[]
--- @param runner_config runtest.RunnerConfig
--- @param start_config runtest.StartConfig
--- @return runtest.RunSpec
local function run_psql(psql_args, runner_config, start_config)
  local command = utils.build_command_line(
    { "psql", resolve_database_url(runner_config), "-X", "-v", "ON_ERROR_STOP=1" },
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
function M.commands.line(runner_config)
  local sql_query = sql_ts.current_query()
  return psql_command_spec(runner_config, { "-c", sql_query })
end

--- @param runner_config runtest.RunnerConfig
--- @return runtest.CommandSpec
function M.commands.file(runner_config)
  local filename = vim.fn.expand("%:p")
  if filename == "" then
    error({ message = "No file path for current buffer", level = vim.log.levels.ERROR })
  end

  return psql_command_spec(runner_config, { "-f", filename })
end

--- @param runner_config runtest.RunnerConfig
function M.select_context(runner_config)
  local bufnr = vim.api.nvim_get_current_buf()
  local env_keys = get_database_url_env_vars(runner_config)

  vim.ui.select(env_keys, {
    prompt = "Select psql context",
    format_item = function(key)
      return key
    end,
  }, function(selected_key)
    if selected_key == nil then
      return
    end

    buffer_context.set_buffer_context(bufnr, selected_key)
    vim.notify("psql context set to " .. selected_key, vim.log.levels.INFO)
  end)
end

return M
