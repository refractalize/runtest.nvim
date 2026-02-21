local sql_ts = require("runtest.languages.sql")
local utils = require("runtest.utils")

--- @class M: runtest.RunnerConfig
local M = {
  name = "psql",
  output_profile = {
    file_patterns = { },
    colorize = false,
    render_header = false,
    always_open = true,
  },
}

local run_test_context_buf_var = "run_test_context"

--- @param database_url string
local function resolve_database_url(database_url)
  if database_url == "DATABASE_URL" or vim.startswith(database_url, "DATABASE_URL_") then
    local env_url = vim.env[database_url]
    if type(env_url) ~= "string" or env_url == "" then
      error({ message = "Environment variable is empty or missing: " .. database_url, level = vim.log.levels.ERROR })
    end
    return env_url
  end

  return database_url
end

local function database_url()
  local bufnr = vim.api.nvim_get_current_buf()
  local context = vim.b[bufnr][run_test_context_buf_var]
  if type(context) == "string" and context ~= "" then
    return resolve_database_url(context)
  end

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

--- @param runner_config runtest.RunnerConfig
function M.select_context(runner_config)
  local bufnr = vim.api.nvim_get_current_buf()
  local env = vim.fn.environ()
  local env_keys = {}

  for key, _ in pairs(env) do
    if key == "DATABASE_URL" or vim.startswith(key, "DATABASE_URL_") then
      table.insert(env_keys, key)
    end
  end

  table.sort(env_keys)

  if #env_keys == 0 then
    vim.notify("No DATABASE_URL or DATABASE_URL_* environment variables found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(env_keys, {
    prompt = "Select psql context",
    format_item = function(key)
      return key
    end,
  }, function(selected_key)
    if selected_key == nil then
      return
    end

    vim.b[bufnr][run_test_context_buf_var] = selected_key
    vim.notify("psql context set to " .. selected_key, vim.log.levels.INFO)
  end)
end

--- @param runner_config runtest.RunnerConfig
--- @param context string
function M.set_context(runner_config, context)
  if type(context) ~= "string" or context == "" then
    error({ message = "Context must be a non-empty string", level = vim.log.levels.ERROR })
  end

  local bufnr = vim.api.nvim_get_current_buf()
  vim.b[bufnr][run_test_context_buf_var] = context
end

return M
