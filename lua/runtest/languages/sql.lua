local utils = require("runtest.languages.utils")

local function get_query()
  return vim.treesitter.query.parse(
    "sql",
    [[
      (statement) @node
    ]]
  )
end

local function node_span_size(node)
  local start_row, start_col, end_row, end_col = node:range()
  return (end_row - start_row) * 100000 + (end_col - start_col)
end

local function trim(text)
  return text:gsub("^%s+", ""):gsub("%s+$", "")
end

--- @param line_number integer
--- @param node TSNode
--- @return boolean
local function node_contains_line(line_number, node)
  local start_row, _, end_row, _ = node:range()
  local row = line_number - 1
  return start_row <= row and row <= end_row
end

--- @param bufnr integer
--- @param line_number integer
--- @return string
local function current_query(bufnr, line_number)
  if type(bufnr) ~= "number" or bufnr <= 0 then
    error({ message = "A valid buffer number is required", level = vim.log.levels.ERROR })
  end

  if type(line_number) ~= "number" or line_number <= 0 then
    error({ message = "A valid line number is required", level = vim.log.levels.ERROR })
  end

  local query = get_query()
  local matches = utils.find_matches(query, nil, bufnr)
  local surrounding_matches = vim.tbl_filter(function(match)
    return node_contains_line(line_number, match._node)
  end, matches)

  if #surrounding_matches == 0 then
    error({ message = "No SQL query found at line " .. line_number, level = vim.log.levels.WARN })
  end

  local best_match = surrounding_matches[1]
  for i = 2, #surrounding_matches do
    if node_span_size(surrounding_matches[i]._node) < node_span_size(best_match._node) then
      best_match = surrounding_matches[i]
    end
  end

  local sql_query = trim(vim.treesitter.get_node_text(best_match._node, bufnr))
  if sql_query == "" then
    error({ message = "No SQL query found at line " .. line_number, level = vim.log.levels.WARN })
  end

  return sql_query
end

function get_query_lines()
  local buf = vim.api.nvim_get_current_buf()
  local query = get_query()
  local matches = utils.find_matches(query)

  return vim.tbl_map(function(match)
    local node = match._node
    local start_row = node:start()
    return start_row + 1
  end, matches)
end

return {
  current_query = current_query,
  get_query_lines = get_query_lines,
}
