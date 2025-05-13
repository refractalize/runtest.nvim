--- @class OutputHistory
local OutputHistory = {}
OutputHistory.__index = OutputHistory

--- @class OutputHistoryEntry
--- @field output_lines string[]
--- @field exit_code number
--- @field profile Profile
--- @field start_time [number, number]
--- @field end_time [number, number]
--- @field debug_spec dap.Configuration?
--- @field run_spec RunSpec?

function OutputHistory:new()
  --- @class OutputHistory
  local self = setmetatable({}, OutputHistory)
  self.history = {}
  self.current_index = 1
  self.max_entries = 10
  return self
end

function OutputHistory:add_entry(entry)
  if #self.history >= self.max_entries then
    table.remove(self.history, 1)
  end
  table.insert(self.history, entry)
  self.current_index = #self.history
end

function OutputHistory:next_entry()
  if self.current_index < #self.history then
    self.current_index = self.current_index + 1
  end
end

function OutputHistory:previous_entry()
  if self.current_index > 1 then
    self.current_index = self.current_index - 1
  end
end

function OutputHistory:get_current_entry()
  return self.history[self.current_index]
end

return OutputHistory
