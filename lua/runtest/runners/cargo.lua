local rust_ts = require("runtest.languages.rust")
local utils = require("runtest.utils")

--- @class M: runtest.RunnerConfig
local M = {}

M.name = "cargo"
M.commands = {}

-- Match common Rust error locations in cargo test output
--  - compiler messages: `--> src/lib.rs:10:5`
--  - panic lines: `src/lib.rs:10:5`
--  - backtraces: `at src/lib.rs:10:5`
M.file_patterns = {
  "\\v^\\s*--\\> (\\f+):(\\d+):(\\d+)",
  "\\v at (\\f+):(\\d+):(\\d+)",
}

-- Treat toolchain/registry files as external for navigation convenience
M.external_file_patterns = {
  "^/",
}

--- Build cargo arguments with defaults and user-specified args
--- @param runner_config runtest.RunnerConfig
--- @param args string[]
--- @param start_config runtest.StartConfig
local function cargo_args(runner_config, args, start_config)
  return utils.build_command_line({ "--color", "always" }, args, runner_config.args, start_config.args)
end

--- @param runner_config runtest.RunnerConfig
--- @param args string[]
--- @param start_config runtest.StartConfig
local function run_cargo_test(runner_config, cwd, args, start_config)
  return {
    utils.build_command_line({ "cargo", "test" }, cargo_args(runner_config, args, start_config)),
    {
      env = vim.tbl_extend("force", { ["CARGO_TERM_COLOR"] = "always" }, runner_config.env or {}),
      cwd = cwd,
    },
  }
end

--- Debug adapter setup for Rust varies by user (codelldb, lldb, etc.).
--- For now, provide a clear error when debug is requested.
local function debug_not_implemented()
  error({ message = "Debug for cargo tests is not implemented", level = vim.log.levels.WARN })
end

--- Create a profile for cargo test with provided args
--- @param runner_config runtest.RunnerConfig
--- @param args string[]
local function cargo_profile(runner_config, args)
  local cwd = vim.fs.root(0, "Cargo.toml")
  return {
    runner_config = runner_config,
    --- @param start_config runtest.StartConfig
    debug_spec = function(start_config)
      return debug_not_implemented()
    end,
    --- @param start_config runtest.StartConfig
    run_spec = function(start_config)
      return run_cargo_test(runner_config, cwd, args, start_config)
    end,
  }
end

--- Find all annotated test functions in the current buffer using Tree-sitter
--- Mirrors the query used in languages/rust.lua but searches full tree.
--- @return string[]
--- @param runner_config runtest.RunnerConfig
--- @returns Profile
function M.commands.line(runner_config)
  local names = rust_ts.line_tests()

  if #names == 0 then
    error({ message = "No tests found", level = vim.log.levels.WARN })
  end

  local args = vim.list_extend(names, { '--', '--exact' })

  return cargo_profile(runner_config, args)
end

--- @param runner_config runtest.RunnerConfig
--- @returns Profile
function M.commands.file(runner_config)
  local names = rust_ts.file_tests()

  if #names == 0 then
    error({ message = "No tests found", level = vim.log.levels.WARN })
  end

  return cargo_profile(runner_config, names)
end

--- @param runner_config runtest.RunnerConfig
--- @returns Profile
function M.commands.all(runner_config)
  return cargo_profile(runner_config, {})
end

return M
