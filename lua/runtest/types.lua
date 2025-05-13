--- @class (exact) runtest.PartialConfig
--- @field open_output_on_failure? boolean --- Whether to open the output window on failure
--- @field close_output_on_success? boolean --- Whether to close the output window on success
--- @field windows? { output?: runtest.PartialWindowProfile, terminal?: runtest.PartialWindowProfile }
--- @field filetypes? { [string]: runtest.PartialRunnerConfig }

--- @class (exact) runtest.PartialWindowProfile
--- @field vertical? boolean --- Whether the current window should be split vertically (true) or horizontally (false)
--- @field size? number --- The size of the window as a fraction of the of the current screen (0.0 to 1.0)
--- @field min? number --- The minimum size of the window in lines
--- @field max? number --- The maximum size of the window in lines

--- @class (exact) runtest.PartialRunnerConfig
--- @field args? string[] --- Extra arguments to pass to the runner
local M = {}

return M
