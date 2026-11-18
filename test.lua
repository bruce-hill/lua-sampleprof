local sample = require('sampleprof')

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
local profile = sample(1,100,function(n)
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
local cprofile = sample(1, 100, function()
    for i=1,300 do
        local s = string.rep("x", 2^20) -- call
        s = nil -- next
    end
end)
local callsamples = cprofile[('test.lua:%d'):format(callline)] or 0
local nextsamples = cprofile[('test.lua:%d'):format(nextline)] or 0
assert(callsamples > 5 * nextsamples,
    ("C call got %d samples, the following line got %d"):format(callsamples, nextsamples))

-- Print a heatmap of the results:
if arg[1] == '-p' then
    local f = io.open('test.lua')
    local maxline = 0
    local lines = {}
    for i=1,9999 do
        local line = f:read("l")
        if not line then break end
        lines[i] = line
        maxline = math.max(#line, maxline)
    end

    local max, total = 0, 0
    for k,v in pairs(profile) do
        local filename = k:match("([^:]*):")
        if filename == 'test.lua' then
            max = math.max(max, v)
            total = total + v
        end
    end

    for i, line in ipairs(lines) do
        local count = (profile[("test.lua:%d"):format(i)] or 0)
        local percentmax = count/(max+1)
        local k = math.floor(6*percentmax^.25)
        local r,g,b = k+math.min(k,5-k),5-k+math.min(k,5-k),0
        if count == 0 then r,g,b = 2,2,1 end
        local color = 16+36*r+6*g+b
        print(("\x1b[2m%3d\x1b[0m \x1b[38;5;%dm%s%s\x1b[0m"):format(i, color, line, (" "):rep(maxline-#line)))
    end
end
