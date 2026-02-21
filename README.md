# 🧪 runtest.nvim

A Neovim plugin for running tests directly within your editor.

## Features

- **Run tests** at different scopes:
  - 🎯 Single test under cursor
  - 📄 All tests in current file
  - 📦 All tests in project
- **Debugging support** via Neovim's DAP integration
- **Smart output window** with:
  - 🎨 Colorized test output
  - 🧠 Automatic error parsing
  - 📚 Output history navigation
- **Test navigation**:
  - ⏭️ Jump between test errors and source code
  - 📋 Send test errors to quickfix list
  - 📋 Send test errors to fzf-lua

## Supported Languages & Test Frameworks

- Python (pytest)
- JavaScript/TypeScript (Jest)
- C# (.NET)
- Ruby (Rails)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'runtest.nvim',
  dependencies = {
    -- Optional: for colorized output
    'm00qek/baleia.nvim',
    -- Optional: for fzf-lua integration
    'ibhagwan/fzf-lua',
    -- Optional: for DAP integration
    'mfussenegger/nvim-dap',
    -- Optional: for Python DAP integration
    'mfussenegger/nvim-dap-python',
  }
  --- @type runtest.PartialConfig
  opts = {
  }
}
```

## Default Configuration

```lua
{
    -- Open the output window automatically on test failure
    open_output_on_failure = false,
    -- Open the output window automatically on test success
    close_output_on_success = false,
    windows = {
      -- Window position for the output window
      output = {
        vertical = true,
      },
      -- Window position for the terminal window
      terminal = {
        vertical = false,
        size = 0.25,
        min = 10,
        max = 40,
      },
    },
    filetypes = {
      cs = require("runtest.runners.dotnet"),
      ruby = require('runtest.runners.rails'),
      python = require("runtest.runners.pytest"),
      typescriptreact = require("runtest.runners.jest"),
      typescript = require("runtest.runners.jest"),
      javascriptreact = require("runtest.runners.jest"),
      javascript = require("runtest.runners.jest"),
    },
}
```

## Usage

### Commands

#### API Reference

##### Setup and Configuration
- `setup(config)` - Configure the plugin with custom settings

##### Test Running
- `run_line_tests([start_config])` - Run test under cursor
- `run_file_tests([start_config])` - Run all tests in current file
- `run_all_tests([start_config])` - Run all tests in project
- `run_lint([start_config])` - Run linting (if configured)
- `run_build([start_config])` - Run build (if configured)

##### Test Debugging
- `debug_line_tests([start_config])` - Debug test under cursor using DAP
- `debug_file_tests([start_config])` - Debug all tests in current file
- `debug_all_tests([start_config])` - Debug all tests in project

##### Command Retrieval
- `get_line_tests_command([start_config])` - Get command for running test at cursor
- `get_file_tests_command([start_config])` - Get command for running file tests
- `get_all_tests_command([start_config])` - Get command for running all tests
- `get_lint_command([start_config])` - Get command for linting
- `get_build_command([start_config])` - Get command for building

##### Last Test Management
- `run_last([start_config])` - Re-run the last test
- `debug_last([start_config])` - Debug the last test
- `goto_last()` - Jump to the location of the last executed test
- `last_command_spec()` - Get information about the last test run

##### Window Management
- `open_output([new_window_command])` - Open the test output window
- `open_terminal([new_window_command])` - Open the terminal window

##### Navigation
- `goto_next_entry()` - Navigate to the next error in output
- `goto_previous_entry()` - Navigate to the previous error in output
- `send_entries_to_quickfix()` - Send error locations to quickfix list
- `send_entries_to_fzf()` - Send error locations to fzf-lua for navigation

##### Output History
- `next_output_history()` - Show the next output history entry
- `previous_output_history()` - Show the previous output history entry

> Note: Parameters in `[brackets]` are optional

### Output Navigation

In the test output window:
- Press `<CR>` on an error message to jump to the source location

## License

This project is licensed under the terms of the MIT license.
