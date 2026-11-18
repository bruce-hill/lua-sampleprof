# sampleprof - Lua Sample Profiling
Sample profiling is a code profiling technique where you randomly stop a
program and inspect its current state to learn about it. This approach is
faster and less disruptive than observing every line of code as it runs, since
observation has overhead. With a reasonable sample size, it's easy to get a
clear picture of which parts of the codebase are taking up most of the time,
while allowing the code to run almost unaffected.

![Preview](https://bitbucket.org/spilt/sampleprof/downloads/sampleprof.png)

## Building
`make` builds the C core, `sampleprof_core.so`. The library is made of two
files: `sampleprof.lua` (the module you `require`) goes on your
`package.path`, and `sampleprof_core.so` goes on your `package.cpath`. Run
`make test` to build and run the tests, and `make test-moon` to run the
source map test, which requires MoonScript.

## Usage
```lua
local sampleprof = require('sampleprof')
local sample = sampleprof.sample

profile = sample(fn, ...)            -- default options
profile = sample(opts, fn, ...)      -- with options
```
`sample` calls `fn(...)` under the profiler and returns a table mapping
`"file:line"` to a weighted sample count. Each call returns a fresh table.
If `fn` raises an error, `sample` re-raises it after cleaning up.

`opts` is an optional table with these fields:

- `backprop` (default `0.619`) controls how samples propagate up the callstack.
  `0` tallies only the current line. `1` tallies the current line and every
  caller equally. `0.5` gives each caller half the weight of the frame below it.
- `rate` (default `100`) is the average number of samples per millisecond.
- `sourcemap` (optional) maps `"file:line"` keys of the running code to
  `"file:line"` keys of the original source, e.g.
  `{["gen.lua:12"] = "app.xyz:40"}`. Lines without an entry keep their key.
  Remapping happens once, after sampling, so it adds no cost while sampling.
  Samples from several lines that map to the same key are added together.

```lua
local profile = sample({backprop=1, rate=100}, fn, arg1, arg2)
local profile = sample({sourcemap=map}, fn)
```

### Heatmap
`sampleprof.heatmap(profile, filename)` prints the source of `filename` to
stdout, colored by how many samples each line received. Lines with no samples
are shown in gray. Use the original filename here when the profile was
remapped with a `sourcemap`.

```lua
sampleprof.heatmap(profile, 'test.lua')
```

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
