# Testing Repository

This repository contains simple examples. The `function_spy.lua` module
implements an experimental function spying system for Luau. Functions are
executed inside a sandboxed environment where global accesses and basic
operations can be logged. Several settings can be toggled when creating a
`FunctionSpy` instance:

- `varnames`
- `usesimplefunctions`
- `watchoutforloop`
- `spynilglobals`
- `hook_op`
- `hook_op_default_return`

When `hook_op` is enabled, simple arithmetic and equality operators are wrapped
so their usage can be recorded. `watchoutforloop` installs a lightweight
debug hook that aborts execution with `infinitelooperror` when too many
instructions run without returning. Globals accessed in the sandbox are logged
when `spynilglobals` is set.

Running `function_spy.lua` directly will automatically load and execute
`input.lua` if present. The file's execution is hooked so a report is printed
afterward.

See `function_spy.lua` for full details.
