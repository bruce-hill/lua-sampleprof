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
