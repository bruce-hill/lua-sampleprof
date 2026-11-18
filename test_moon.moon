sampleprof = require 'sampleprof'
import sample from sampleprof
import to_lua from require 'moonscript.base'

FILENAME = 'test_moon.moon'

-- Build a sourcemap from the Lua that MoonScript generates for `filename` back
-- to the original MoonScript lines. MoonScript's position map only has entries
-- for some Lua lines, so lines without one take the most recent mapped line.
build_sourcemap = (filename) ->
    f = assert io.open filename
    text = f\read 'a'
    f\close!
    lua_code, posmap = to_lua text
    assert lua_code, posmap
    line_of = (pos) -> select(2, text\sub(1, pos)\gsub('\n', '')) + 1
    lua_lines = select(2, lua_code\gsub('\n', '')) + 1
    sourcemap = {}
    last = 1
    for lua_line = 1, lua_lines
        if pos = posmap[lua_line]
            last = line_of pos
        sourcemap["#{filename}:#{lua_line}"] = "#{filename}:#{last}"
    sourcemap

sourcemap = build_sourcemap FILENAME

source_lines = [line for line in io.lines FILENAME]

linenumber = (pattern) ->
    for n, line in ipairs source_lines
        return n if line\find pattern

foo = ->
    for i=1,1000
        _ = i + 1 -- foo loop

baz = ->
    for i=1,500
        _ = i + 1 -- baz loop

work = (n) ->
    assert n == 23
    for i=1,1000
        foo!
        baz!

collectgarbage 'stop'
profile = sample {backprop: 1, rate: 100, :sourcemap}, work, 23

assert profile

-- Every sampled line in this file should map to a real, non-blank MoonScript line
for key in pairs profile
    line = tonumber key\match "^#{FILENAME\gsub('%p', '%%%0')}:(%d+)$"
    if line
        assert source_lines[line], "#{key} is past the end of #{FILENAME}"
        assert source_lines[line]\find('%S'), "#{key} is a blank line"

-- The 1000-iteration loop should get more samples than the 500-iteration one
fooline = linenumber "%-%-%s*foo loop$"
bazline = linenumber "%-%-%s*baz loop$"
foosamples = profile["#{FILENAME}:#{fooline}"] or 0
bazsamples = profile["#{FILENAME}:#{bazline}"] or 0
assert foosamples > bazsamples,
    "1000-iteration loop got #{foosamples} samples, 500-iteration loop got #{bazsamples}"

-- Time spent inside a C function should be charged to the line that called it,
-- not to the line that runs after the call returns
collectgarbage 'restart'
callline = linenumber "%-%-%s*call$"
nextline = linenumber "%-%-%s*next$"
cprofile = sample {rate: 100, :sourcemap}, ->
    for i=1,300
        s = string.rep "x", 2^20 -- call
        s = nil -- next
callsamples = cprofile["#{FILENAME}:#{callline}"] or 0
nextsamples = cprofile["#{FILENAME}:#{nextline}"] or 0
assert callsamples > 5 * nextsamples,
    "C call got #{callsamples} samples, the following line got #{nextsamples}"

-- Make sure the mapping actually moved these lines, so the checks above couldn't
-- have passed using the generated Lua's line numbers
assert sourcemap["#{FILENAME}:#{callline}"] != "#{FILENAME}:#{callline}",
    "generated Lua line #{callline} already lines up with the MoonScript source"

-- Print a heatmap of the results:
if arg[1] == '-p'
    sampleprof.heatmap profile, FILENAME
