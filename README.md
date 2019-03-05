# sampleprof - Lua Sample Profiling
Sample profiling is a code profiling technique where you randomly stop a
program and inspect its current state to learn about it. This approach is
faster and less disruptive than observing every line of code as it runs, since
observation has overhead. With a reasonable sample size, it's easy to get a
clear picture of which parts of the codebase are taking up most of the time,
while allowing the code to run almost unaffected.

## Usage
The Lua library returns a single function, which takes a function to run,
performs sample profiling on it, and gives a table of results. The results
table is a mapping from `"filename.lua:line"` to number of samples. By default,
samples are propagated up the callstack, with a decay (0.619).
```lua
local sample = require('sampleprof')
local profile = sample(fn)
```
