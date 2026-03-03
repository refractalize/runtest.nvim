local utils = require("runtest.utils")
local buffer_context = require("runtest.buffer_context")

--- @class M: runtest.RunnerConfig
local M = {
  name = "jq",
  output_profile = {
    file_patterns = {},
    colorize = false,
    render_header = false,
    filetype = "json",
    output_window = {
      open = "always",
    },
  },
  commands = {},
}

--- @param runner_config runtest.RunnerConfig
--- @param jq_args string[]
--- @return runtest.CommandSpec
local function jq_command_spec(runner_config, jq_args)
  return {
    runner_config = runner_config,
    run_spec = function(start_config)
      local bufnr = vim.api.nvim_get_current_buf()
      local input_file = buffer_context.get_buffer_context(bufnr)

      local base = { "jq" }
      local tail = input_file and { input_file } or {}

      local command = utils.build_command_line(base, jq_args, runner_config.args, start_config.args, tail)
      return { command }
    end,
  }
end

--- @param runner_config runtest.RunnerConfig
--- @return runtest.CommandSpec
function M.commands.file(runner_config)
  local filename = vim.fn.expand("%:p")
  if filename == "" then
    error({ message = "No file path for current buffer", level = vim.log.levels.ERROR })
  end

  return jq_command_spec(runner_config, { "-f", filename })
end

--- @param runner_config runtest.RunnerConfig
function M.select_context(runner_config)
  local bufnr = vim.api.nvim_get_current_buf()
  local current_context = buffer_context.get_buffer_context(bufnr)

  vim.ui.input({
    prompt = "Input JSON file (empty to clear): ",
    default = current_context or "",
    completion = "file",
  }, function(input)
    if input == nil then
      return
    end

    if input == "" then
      buffer_context.set_buffer_context(bufnr, nil)
      vim.notify("jq input file cleared", vim.log.levels.INFO)
    else
      buffer_context.set_buffer_context(bufnr, input)
      vim.notify("jq input file set to " .. input, vim.log.levels.INFO)
    end
  end)
end

return M
