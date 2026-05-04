local run_test_context_buf_var = "run_test_context"
local run_test_context_env_var_buf_var = "run_test_context_env_var"

--- @param context string
--- @return string
local function resolve_context_env_var(context)
  if type(context) ~= "string" or context == "" then
    error({
      message = "Context environment variable must be a non-empty string",
      level = vim.log.levels.ERROR,
    })
  end

  local value = vim.env[context]
  if type(value) ~= "string" or value == "" then
    error({
      message = "Context environment variable is empty or missing: " .. context,
      level = vim.log.levels.ERROR,
    })
  end

  return value
end

--- @param runner_config runtest.RunnerConfig
--- @return string | nil
local function get_default_context_env_var(runner_config)
  if type(runner_config) ~= "table" then
    return nil
  end

  local default_context_env_var = runner_config.default_context_env_var
  if type(default_context_env_var) == "string" and default_context_env_var ~= "" then
    return default_context_env_var
  end

  return nil
end

--- @param runner_config runtest.RunnerConfig
--- @param env_var_name string
--- @return boolean
local function env_var_matches_context_pattern(runner_config, env_var_name)
  local context_env_var_pattern = runner_config.context_env_var_pattern
  if type(context_env_var_pattern) == "string" then
    local pattern = vim.fn.glob2regpat(context_env_var_pattern)
    return vim.fn.match(env_var_name, pattern) ~= -1
  elseif type(context_env_var_pattern) == "function" then
    local ok, result = pcall(context_env_var_pattern, env_var_name)
    return ok and result == true
  end

  return false
end

--- @param runner_config runtest.RunnerConfig
--- @return string[]
local function get_context_env_vars(runner_config)
  local env_vars = {}
  local default_context_env_var = get_default_context_env_var(runner_config)

  for key, _ in pairs(vim.fn.environ()) do
    if key == default_context_env_var or env_var_matches_context_pattern(runner_config, key) then
      table.insert(env_vars, key)
    end
  end

  table.sort(env_vars)

  return env_vars
end

--- @param buffer number
local function clear_buffer_context(buffer)
  pcall(vim.api.nvim_buf_del_var, buffer, run_test_context_buf_var)
  pcall(vim.api.nvim_buf_del_var, buffer, run_test_context_env_var_buf_var)
end

--- @param buffer number
--- @param context string | nil
local function set_buffer_context(buffer, context)
  if context == nil then
    clear_buffer_context(buffer)
    return
  end

  pcall(vim.api.nvim_buf_del_var, buffer, run_test_context_env_var_buf_var)
  vim.api.nvim_buf_set_var(buffer, run_test_context_buf_var, context)
end

--- @param buffer number
--- @param context_env_var string | nil
local function set_buffer_context_env_var(buffer, context_env_var)
  if context_env_var == nil then
    clear_buffer_context(buffer)
    return
  end

  pcall(vim.api.nvim_buf_del_var, buffer, run_test_context_buf_var)
  vim.api.nvim_buf_set_var(buffer, run_test_context_env_var_buf_var, context_env_var)
end

--- @param buffer number
--- @return string | nil
local function get_raw_buffer_context(buffer)
  local ok, context = pcall(vim.api.nvim_buf_get_var, buffer, run_test_context_buf_var)
  if ok and type(context) == "string" and context ~= "" then
    return context
  end

  return nil
end

--- @param buffer number
--- @return string | nil
local function get_buffer_context_env_var(buffer)
  local ok, context_env_var = pcall(vim.api.nvim_buf_get_var, buffer, run_test_context_env_var_buf_var)
  if ok and type(context_env_var) == "string" and context_env_var ~= "" then
    return context_env_var
  end

  return nil
end

--- @param buffer number
--- @param runner_config runtest.RunnerConfig | nil
--- @return string | nil
local function get_buffer_context(buffer, runner_config)
  local context = get_raw_buffer_context(buffer)
  if context ~= nil then
    return context
  end

  local context_env_var = get_buffer_context_env_var(buffer)
  if context_env_var ~= nil then
    return resolve_context_env_var(context_env_var)
  end

  if runner_config == nil then
    return nil
  end

  local default_context_env_var = get_default_context_env_var(runner_config)
  if default_context_env_var ~= nil then
    return resolve_context_env_var(default_context_env_var)
  end

  error({
    message = "Could not get context for buffer",
    level = vim.log.levels.ERROR,
  })
end

--- @param buf number
--- @param runner_config runtest.RunnerConfig
local function select_context(buf, runner_config)
  local env_keys = get_context_env_vars(runner_config)
  if vim.tbl_isempty(env_keys) then
    error({
      message = "No context environment variables found",
      level = vim.log.levels.ERROR,
    })
  end

  local current_context = get_buffer_context_env_var(buf)

  vim.ui.select(env_keys, {
    prompt = "Select context",
    format_item = function(key)
      if key == current_context then
        return "✓ " .. key
      end

      return "  " .. key
    end,
  }, function(selected_key)
    if selected_key == nil then
      return
    end

    set_buffer_context_env_var(buf, selected_key)
    vim.notify("Context set to " .. selected_key, vim.log.levels.INFO)
  end)
end

--- @param buf number
local function edit_context(buf)
  local current_context = get_raw_buffer_context(buf)

  vim.ui.input({
    prompt = "Edit context (empty to clear): ",
    default = current_context or "",
  }, function(input)
    if input == nil then
      return
    end

    if input == "" then
      set_buffer_context(buf, nil)
      vim.notify("Context cleared", vim.log.levels.INFO)
      return
    end

    set_buffer_context(buf, input)
    vim.notify("Context set to " .. input, vim.log.levels.INFO)
  end)
end

return {
  set_buffer_context = set_buffer_context,
  set_buffer_context_env_var = set_buffer_context_env_var,
  get_buffer_context = get_buffer_context,
  select_context = select_context,
  edit_context = edit_context,
}
