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

--- @class runtest.PartialRunnerConfig
--- @field args? string[]
--- @field name? string
--- @field file_patterns? (string | fun(profile: runtest.Profile, line: string): ([string, string, string, string] | nil))[]
--- @field line_tests? fun(): runtest.Profile
--- @field all_tests? fun(): runtest.Profile
--- @field file_tests? fun(): runtest.Profile
local M = {}

return M
