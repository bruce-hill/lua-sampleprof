local sampleprof = require('sampleprof')
local sample = sampleprof.sample

local foo = function()
    for i=1,1000 do
        local _ = i + 1
    end
end

local baz = function()
    for i=1,500 do
        local _ = i + 1
    end
end

collectgarbage('stop')
local profile = sample({backprop=1, rate=100}, function(n)
    assert(n == 23)
    for i=1,1000 do
        foo()
        baz()
    end
end, 23)

assert(profile)

-- Time spent inside a C function should be charged to the line that called it,
-- not to the line that runs after the call returns
collectgarbage('restart')
local function linenumber(pattern)
    local n = 0
    for line in io.lines('test.lua') do
        n = n + 1
        if line:find(pattern) then return n end
    end
end
local callline = linenumber("%-%-%s*call$")
local nextline = linenumber("%-%-%s*next$")
local cprofile = sample({rate=100}, function()
    for i=1,300 do
        local s = string.rep("x", 2^20) -- call
        s = nil -- next
    end
end)
local callsamples = cprofile[('test.lua:%d'):format(callline)] or 0
local nextsamples = cprofile[('test.lua:%d'):format(nextline)] or 0
assert(callsamples > 5 * nextsamples,
    ("C call got %d samples, the following line got %d"):format(callsamples, nextsamples))

-- A sourcemap rewrites keys after sampling: every test.lua line should come out
-- as original.lua, with the same line number plus 100
local sourcemap = {}
for i=1,200 do
    sourcemap[('test.lua:%d'):format(i)] = ('original.lua:%d'):format(i+100)
end
local mapped = sample({rate=100, sourcemap=sourcemap}, function()
    for i=1,300 do
        foo()
    end
end)
local mappedsamples = 0
for key, count in pairs(mapped) do
    assert(not key:find('^test%.lua:'), "unmapped key: "..key)
    if key:find('^original%.lua:') then mappedsamples = mappedsamples + count end
end
assert(mappedsamples > 0, "no samples landed on mapped lines")

-- Print a heatmap of the results:
if arg[1] == '-p' then
    sampleprof.heatmap(profile, 'test.lua')
end
