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

local function current_query()
  local buf = vim.api.nvim_get_current_buf()
  local query = get_query()
  local matches = utils.find_surrounding_matches(query)

  if #matches == 0 then
    error({ message = "No SQL query found at cursor", level = vim.log.levels.WARN })
  end

  local best_match = matches[1]
  for i = 2, #matches do
    if node_span_size(matches[i]._node) < node_span_size(best_match._node) then
      best_match = matches[i]
    end
  end

  local sql_query = trim(vim.treesitter.get_node_text(best_match._node, buf))
  if sql_query == "" then
    error({ message = "No SQL query found at cursor", level = vim.log.levels.WARN })
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
