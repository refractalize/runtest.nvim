local javascript_ts = require("runtest.languages.javascript")

--- @class JestProfile: runtest.CommandSpec
--- @field cwd string

--- @class M: runtest.RunnerConfig
local M = {
  name = "vitest",
  output_profile = {},
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
          local matches = vim.fn.matchlist(line, "\\v(\\f+):(\\d+):(\\d+)")
          if matches[1] ~= nil then
            matches[2] = cwd .. "/" .. matches[2]
            return matches
          end
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
function M.all_tests(runner_config)
  return vitest_profile({})
end

--- @param runner_config runtest.RunnerConfig
--- @returns runtest.CommandSpec
function M.file_tests(runner_config)
  local filename = vim.fn.expand("%:p")
  return vitest_profile({ filename })
end

--- @param runner_config runtest.RunnerConfig
--- @returns runtest.CommandSpec
function M.line_tests(runner_config)
  local test_context = javascript_ts.line_tests()
  local pattern = vim.fn.join(test_context, " ")
  local test_filename = vim.fn.expand("%:p")
  return vitest_profile({ test_filename, "--testNamePattern", pattern })
end

return M
