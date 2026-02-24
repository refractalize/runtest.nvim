--- @class (exact) runtest.PartialConfig
--- @field history? runtest.OutputHistoryConfig
--- @field windows? { output?: runtest.PartialOutputWindowConfig, terminal?: runtest.PartialTerminalWindowConfig }
--- @field filetypes? { [string]: runtest.PartialRunnerConfig | string }
--- @field runners? { [string]: runtest.PartialRunnerConfig }

--- @class (exact) runtest.PartialOutputWindowConfig
--- @field open? runtest.OutputWindowShowCondition
--- @field close? runtest.OutputWindowShowCondition
--- @field layout? runtest.PartialWindowLayout

--- @class (exact) runtest.PartialTerminalWindowConfig
--- @field layout? runtest.PartialWindowLayout

--- @class (exact) runtest.PartialWindowLayout
--- @field vertical? boolean --- Whether the current window should be split vertically (true) or horizontally (false)
--- @field size? number --- The size of the window as a fraction of the of the current screen (0.0 to 1.0)
--- @field min? number --- The minimum size of the window in lines
--- @field max? number --- The maximum size of the window in lines

--- @class (exact) runtest.PartialRunnerConfig
--- @field args? string[]
--- @field name? string
--- @field env? { [string]: string }
--- @field output_profile? runtest.OutputProfile
--- @field commands? { [string]: fun(runner_config: runtest.RunnerConfig): runtest.CommandSpec }
--- @field select_context? fun(runner_config: runtest.RunnerConfig)
--- @field set_context? fun(runner_config: runtest.RunnerConfig, context: string)
local M = {}

return M
