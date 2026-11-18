-- sampleprof: a Lua sample profiling library by Bruce Hill
-- The sampling itself happens in the C module sampleprof_core. This file
-- handles options, source maps, and printing reports.

local core = require('sampleprof_core')

local DEFAULT_BACKPROP = 0.619
local DEFAULT_RATE = 100

-- Frames from this file are left out of profiles
local SOURCE = debug.getinfo(1, 'S').source

-- Rewrite "file:line" keys through a sourcemap. Keys without an entry are kept
-- as-is, and counts for keys that map to the same target are added together.
local function remap(profile, sourcemap)
    local mapped = {}
    for key, count in pairs(profile) do
        local target = sourcemap[key] or key
        mapped[target] = (mapped[target] or 0) + count
    end
    return mapped
end

-- sample([opts,] fn, ...) runs fn(...) under the profiler and returns a table
-- mapping "file:line" to a weighted sample count
local function sample(opts, ...)
    if type(opts) == 'function' then
        return sample({}, opts, ...)
    elseif type(opts) ~= 'table' then
        error('sampleprof.sample: expected an options table or a function', 2)
    end

    local fn = ...
    if type(fn) ~= 'function' then
        error('sampleprof.sample: expected a function to profile', 2)
    end
    local backprop = opts.backprop or DEFAULT_BACKPROP
    if type(backprop) ~= 'number' then
        error("sampleprof.sample: option 'backprop' must be a number", 2)
    end
    local rate = opts.rate or DEFAULT_RATE
    if type(rate) ~= 'number' then
        error("sampleprof.sample: option 'rate' must be a number", 2)
    end
    local sourcemap = opts.sourcemap
    if sourcemap ~= nil and type(sourcemap) ~= 'table' then
        error("sampleprof.sample: option 'sourcemap' must be a table", 2)
    end

    local profile = core.collect(SOURCE, backprop, rate, ...)
    -- Remap only now that sampling is finished, so it costs nothing while sampling
    if sourcemap then
        profile = remap(profile, sourcemap)
    end
    return profile
end

-- Print the lines of `filename`, colored by how many samples each line got
local function heatmap(profile, filename)
    local lines = {}
    for line in io.lines(filename) do
        lines[#lines+1] = line
    end

    local prefix = filename..':'
    local max, maxline = 0, 0
    for key, count in pairs(profile) do
        if key:sub(1, #prefix) == prefix then
            max = math.max(max, count)
        end
    end
    for _, line in ipairs(lines) do
        maxline = math.max(#line, maxline)
    end

    for i, line in ipairs(lines) do
        local count = profile[prefix..i] or 0
        local percentmax = count/(max+1)
        local k = math.floor(6*percentmax^.25)
        local r,g,b = k+math.min(k,5-k),5-k+math.min(k,5-k),0
        if count == 0 then r,g,b = 2,2,1 end
        local color = 16+36*r+6*g+b
        print(("\x1b[2m%3d\x1b[0m \x1b[38;5;%dm%s%s\x1b[0m"):format(i, color, line, (" "):rep(maxline-#line)))
    end
end

return {
    sample = sample,
    heatmap = heatmap,
}
