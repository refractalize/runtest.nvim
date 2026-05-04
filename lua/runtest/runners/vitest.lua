local javascript_ts = require("runtest.languages.javascript")
local vitest_stack_pattern = "\\v%(\\S+\\s*\\(|at\\s+.{-}\\(|)(file://)?([^()[:space:]]+):(\\d+):(\\d+)\\)?$"

--- @param line string
--- @param cwd string
--- @return [string, string, string, string] | nil
local function match_vitest_stack_frame(line, cwd)
  local matches = vim.fn.matchlist(line, vitest_stack_pattern)
  if matches[1] == nil then
    return nil
  end

  if matches[3]:sub(1, 1) ~= "/" then
    matches[3] = cwd .. "/" .. matches[3]
  end

  return { matches[1], matches[3], matches[4], matches[5] }
end

--- @class JestProfile: runtest.CommandSpec
--- @field cwd string

--- @class M: runtest.RunnerConfig
local M = {
  name = "vitest",
  output_profile = {
    file_patterns = {
      vitest_stack_pattern,
    },
  },
  commands = {},
}

--- @param args string[]
--- @param start_config runtest.StartConfig
--- @param cwd string
function run_vitest(args, start_config, cwd)
  return {
    vim.list_extend({ "npm", "exec", "--", "vitest", "run" }, vim.list_extend(start_config.args or {}, args or {})),
    {
      env = { ["FORCE_COLOR"] = "true" },
      cwd = cwd,
    },
  }
end

function debug_vitest(args, start_config)
  return {
    type = "pwa-node",
    request = "launch",
    name = "Debug Vitest Tests",
    trace = true, -- include debugger info
    runtimeExecutable = "node",
    runtimeArgs = vim.list_extend(
      { "./node_modules/jest/bin/jest.js", "--runInBand" },
      vim.list_extend(start_config.args or {}, args or {})
    ),
    rootPath = "${workspaceFolder}",
    cwd = "${workspaceFolder}",
    console = "integratedTerminal",
    internalConsoleOptions = "neverOpen",
  }
end

--- @param args string[]
--- @return JestProfile
function vitest_profile(args)
  local cwd = javascript_ts.get_node_root_directory()
  return {
    runner_config = M,
    output_profile = {
      file_patterns = {
        --- @param line string
        function(line)
          return match_vitest_stack_frame(line, cwd)
        end,
      },
    },
    --- @param start_config runtest.StartConfig
    debug_spec = function(start_config)
      return debug_vitest(args, start_config)
    end,
    --- @param start_config runtest.StartConfig
    run_spec = function(start_config)
      return run_vitest(args, start_config, cwd)
    end,
  }
end

--- @param runner_config runtest.RunnerConfig
--- @returns runtest.CommandSpec
function M.commands.all(runner_config)
  return vitest_profile({})
end

--- @param runner_config runtest.RunnerConfig
--- @returns runtest.CommandSpec
function M.commands.file(runner_config)
  local filename = vim.fn.expand("%:p")
  return vitest_profile({ filename })
end

--- @param runner_config runtest.RunnerConfig
--- @returns runtest.CommandSpec
function M.commands.line(runner_config)
  local test_context = javascript_ts.line_tests()
  local pattern = vim.fn.join(test_context, " ")
  local test_filename = vim.fn.expand("%:p")
  return vitest_profile({ test_filename, "--testNamePattern", pattern })
end

return M
