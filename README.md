# sampleprof - Lua Sample Profiling
Sample profiling is a code profiling technique where you randomly stop a
program and inspect its current state to learn about it. This approach is
faster and less disruptive than observing every line of code as it runs, since
observation has overhead. With a reasonable sample size, it's easy to get a
clear picture of which parts of the codebase are taking up most of the time,
while allowing the code to run almost unaffected.

![Preview](https://bitbucket.org/spilt/sampleprof/downloads/sampleprof.png)

## Usage
The Lua library returns a single function with the signature:
```lua
profile = sample([backprop], [rate], fn, ...)
```
It calls `fn(...)` under the profiler and returns a table mapping
`"filename.lua:line"` to a weighted sample count. Each call returns a fresh
table.

- `backprop` (default `0.619`) controls how samples propagate up the callstack.
  `0` tallies only the current line. `1` tallies the current line and every
  caller equally. `0.5` gives each caller half the weight of the frame below it.
- `rate` (default `100`) is the average number of samples per millisecond.

```lua
local sample = require('sampleprof')
local profile = sample(fn, arg1, arg2)
local profile = sample(1, 100, fn, arg1, arg2)  -- backprop=1, rate=100
```

If `fn` raises an error, `sample` re-raises it after cleaning up.

## Limitations
- **Samples land on the next line executed.** The signal only arms a Lua hook,
  so a sample taken in the middle of a Lua line is charged to the next line
  that runs. Time spent inside a C function is charged to the Lua line that
  called it, even though it's only observed when the call returns.
- **Wall-clock time.** Sampling uses a real-time timer (`ITIMER_REAL`), so time
  spent blocked on I/O or sleeping is sampled too. A CPU-time timer
  (`ITIMER_PROF`) only ticks with the kernel clock, which is too coarse to honor
  `rate`.
- **Process-wide timer and `SIGALRM`.** `sample` replaces the `SIGALRM` handler,
  cancels any pending `alarm()`, and restores the previous handler on return.
  Don't use `SIGALRM` or `alarm()` in code being profiled.
- **Not reentrant, and coroutines aren't covered.** Don't call `sample` from
  inside a profiled function. The hook is installed only on the thread that
  called `sample`, so code running in coroutines isn't sampled.
