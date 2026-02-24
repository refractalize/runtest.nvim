local run_test_context_buf_var = "run_test_context"

local function set_buffer_context(buffer, context)
  vim.api.nvim_buf_set_var(buffer, run_test_context_buf_var, context)
end

local function get_buffer_context(buffer)
  local ok, context = pcall(vim.api.nvim_buf_get_var, buffer, run_test_context_buf_var)
  if ok then
    return context
  else
    return nil
  end
end

return {
  set_buffer_context = set_buffer_context,
  get_buffer_context = get_buffer_context,
}
