--- @class runtest.OutputHistory
--- @field history runtest.OutputHistoryEntry[]
--- @field current_index number
--- @field config runtest.OutputHistoryConfig
local OutputHistory = {}
OutputHistory.__index = OutputHistory

--- @class runtest.OutputHistoryConfig
--- @field max_entries number

--- @class runtest.OutputHistoryEntry
--- @field output_file string | nil
--- @field output_lines string[] | nil
--- @field output_buffer runtest.OutputBuffer | nil
--- @field exit_code number
--- @field command_spec runtest.CommandSpec
--- @field start_time [number, number]
--- @field end_time [number, number]
--- @field debug_spec dap.Configuration?
--- @field run_spec runtest.RunSpec?

function OutputHistory:new()
  --- @class runtest.OutputHistory
  local self = setmetatable({}, OutputHistory)
  self.history = {}
  self.current_index = 1
  self.config = {
    max_entries = 10,
  }
  return self
end

--- @param config runtest.OutputHistoryConfig
function OutputHistory:setup(config)
  self.config = vim.tbl_deep_extend("force", self.config, config or {})
end

--- @param entry runtest.OutputHistoryEntry
function OutputHistory:add_entry(entry)
  if #self.history >= self.config.max_entries then
    table.remove(self.history, 1)
  end
  table.insert(self.history, entry)
  self.current_index = #self.history
end

--- @return runtest.OutputHistoryEntry?
function OutputHistory:next_entry()
  if self.current_index < #self.history then
    self.current_index = self.current_index + 1
  end
  return self.history[self.current_index]
end

--- @return runtest.OutputHistoryEntry?
function OutputHistory:previous_entry()
  if self.current_index > 1 then
    self.current_index = self.current_index - 1
  end
  return self.history[self.current_index]
end

--- @return runtest.OutputHistoryEntry?
function OutputHistory:get_current_entry()
  return self.history[self.current_index]
end

return OutputHistory
