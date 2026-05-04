local utils = require('runtest.languages.utils')

local function get_query()
  return vim.treesitter.query.parse(
    "python",
    [[
      [
        (function_definition name: (_) @function_name)
        (class_definition name: (_) @class_name)
      ] @node
    ]]
  )
end

--- @returns string[]
local function test_path()
  local buf = vim.api.nvim_get_current_buf()

  local query = get_query()

  local matches = utils.find_surrounding_matches(query)

  local test_matches = vim.tbl_filter(function(match)
    if match.function_name then
      return match.function_name[1].text:match("^test")
    elseif match.class_name then
      return match.class_name[1].text:match("^Test")
    end
  end, matches)

  local test_path = vim.tbl_map(function(match)
    if match.function_name then
      return match.function_name[1].text
    elseif match.class_name then
      return match.class_name[1].text
    end
  end, test_matches)

  return test_path
end

local function get_test_lines()
  local query = get_query()
  local matches = utils.find_matches(query)
  local function_name_matches = vim.tbl_map(function(match)
    if match.function_name and match.function_name[1] then
      if match.function_name[1].text:match("^test") then
        local node = match.function_name[1].node
        local start_row, start_col, _ = node:start()

        return start_row + 1
      end
    end
  end, matches)
  return vim.tbl_filter(function(line)
    return line ~= nil
  end, function_name_matches)
end

return {
  test_path = test_path,
  get_test_lines = get_test_lines,
}
