local utils = require("runtest.languages.utils")

--- Build the Tree-sitter query that captures Rust test functions
--- @return vim.treesitter.Query
local function test_query()
  return vim.treesitter.query.parse(
    "rust",
    [[
      (
        (function_item
          name: (identifier) @test_name)
      ) @node
    ]]
  )
end

--- Determine the project root by locating Cargo.toml upwards from buffer path
--- @param buf integer
--- @return string
local function project_root_for_buf(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local dir = vim.fs.dirname(path)
  local found = vim.fs.find("Cargo.toml", { path = dir, upward = true })[1]
  if found then
    return vim.fs.dirname(found)
  else
    error("Could not find Cargo.toml for rust buffer " .. tostring(buf))
  end
end

--- @param filename string
--- @param prefix string
--- @return string
local function try_remove_prefix(filename, prefix)
  local start = filename:find(prefix, 1, true)
  if start ~= nil then
    return filename:sub(start + #prefix)
  end
end

--- Compute file path context relative to project root and return origin and module segments
--- @param buf integer
--- @return {type: 'src' | 'lib' | 'main' | 'tests', segments: string[], tests_filename?: string}
local function file_path_context(buf)
  local filename = vim.api.nvim_buf_get_name(buf)
  local root = project_root_for_buf(buf)

  local root_relative_path = try_remove_prefix(filename, root)

  if not root_relative_path then
    error("File " .. filename .. " not under project root: " .. root)
  end

  path_without_ext = root_relative_path:gsub("%.rs$", "")

  local segments = vim.split(path_without_ext, "/", { trimempty = true })

  if segments[#segments] == "mod" then
    table.remove(segments, #segments)
  end

  if segments[1] == "src" then
    table.remove(segments, 1)
    if segments[1] == "lib" or segments[1] == "main" then
      table.remove(segments, 1)
      return { type = segments[1], segments = segments }
    end

    return { type = "src", segments = segments }
  elseif segments[1] == "tests" then
    table.remove(segments, 1)
    local tests_filename = segments[1]
    table.remove(segments, 1)

    return { type = "tests", segments = segments, tests_filename = tests_filename }
  else
    error("File " .. filename .. " not in src/ or tests/ directory")
  end
end

--- Collect enclosing mod_item names from AST for a node (inner-most to outer-most)
--- @param node TSNode
--- @param buf integer|nil
--- @return string[]
local function enclosing_mod_segments(node, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local segs = {}
  local n = node --- @type TSNode?
  while n do
    if n:type() == "mod_item" then
      local name
      for child in n:iter_children() do
        if child:type() == "identifier" then
          name = vim.treesitter.get_node_text(child, buf)
          break
        end
      end
      if name then
        table.insert(segs, name)
      end
    end
    n = n:parent()
  end
  -- Currently segs are inner->outer; reverse to outer->inner
  for i = 1, math.floor(#segs / 2) do
    segs[i], segs[#segs - i + 1] = segs[#segs - i + 1], segs[i]
  end
  return segs
end

--- Return module path (without test function name) for a node
--- Combines directory-derived modules with enclosing `mod` items.
--- @param node TSNode
--- @param buf integer
--- @return string
local function module_path_for_node(node, buf)
  local path_segs = file_path_context(buf).segments
  local mod_segs = enclosing_mod_segments(node, buf)
  local all = vim.list_extend(path_segs, mod_segs)
  return table.concat(all, "::")
end

--- Check whether a function has a preceding #[test] (or scoped ...::test) attribute
--- Walks previous siblings while they are attribute_item nodes and searches for an
--- identifier named "test" within the attribute subtree.
--- @param func_node TSNode
--- @param buf integer|nil
--- @return boolean
local function has_test_attribute(func_node, buf)
  buf = buf or vim.api.nvim_get_current_buf()

  local function subtree_has_test_identifier(node)
    if node:type() == "identifier" then
      local text = vim.treesitter.get_node_text(node, buf)
      if text == "test" then
        return true
      end
    end
    for child in node:iter_children() do
      if subtree_has_test_identifier(child) then
        return true
      end
    end
    return false
  end

  local prev = func_node:prev_sibling()
  while prev and prev:type() == "attribute_item" do
    for child in prev:iter_children() do
      if child:type() == "attribute" then
        if subtree_has_test_identifier(child) then
          return true
        end
      end
    end
    prev = prev:prev_sibling()
  end

  return false
end

--- Build a fully-qualified test name from a match
--- @param match_node runtest.languages.MatchNode
--- @param buf integer
--- @return string
local function qualify_test_name(match_node, buf)
  local module = module_path_for_node(match_node.node, buf)
  local name = match_node.text
  if module ~= "" and name ~= "" then
    return module .. "::" .. name
  else
    return name
  end
end

--- Get fully-qualified test names for the test(s) surrounding the cursor
--- @return string[]
local function line_tests()
  local query = test_query()

  local matches = utils.find_surrounding_matches(query)

  local buf = vim.api.nvim_get_current_buf()
  local test_names = vim
    .iter(matches)
    :filter(function(match)
      return has_test_attribute(match._node, buf)
    end)
    :map(function(match)
      return qualify_test_name(match.test_name[1], buf)
    end)
    :totable()

  return test_names
end

local function file_tests()
  local query = test_query()

  local matches = utils.find_matches(query)

  if #matches == 0 then
    return {}
  end

  local buf = vim.api.nvim_get_current_buf()
  local first_test_name = vim.iter(matches):find(function(match)
    return has_test_attribute(match._node, buf)
  end)

  if not first_test_name then
    return {}
  end

  -- We only need a single cargo filter prefix per file
  local file_context = file_path_context(buf)
  if file_context.type == "tests" then
    return { "--test", file_context.tests_filename }
  end
  local prefix = module_path_for_node(first_test_name.test_name[1].node, buf)
  if prefix == "" then
    return {}
  end
  return { prefix .. "::" }
end

return {
  line_tests = line_tests,
  file_tests = file_tests,
}
