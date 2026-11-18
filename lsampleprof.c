/*
* lsampleprof.c
* The C core of a Lua sample profiling library by Bruce Hill. Users should
* require 'sampleprof' (sampleprof.lua), which wraps this module. This module
* exports a single function:
*
*    collect(skipsource, backprop, rate, fn, ...)
*
* that runs `fn` with any extra args, performs sample profiling, and
* returns a table of the results.
*
*    - `skipsource` frames whose source equals this string are left out of the results
*       (the wrapper passes its own source, so it doesn't show up in profiles)
*    - `rate` the average number of samples per millisecond
*    - `backprop` controls how weights are propagated up the callstack. 0 means "only tally
*       the current line", 1 means "tally the current line and everything above it in the
*       callstack equally", 0.5 means "tally each line with half weight of the thing below
*       it in the callstack"
*
*  The results table is a mapping from "file:line" -> number of times a random sample landed on that line
*/

// setitimer() and sigaction() are POSIX/XSI extensions, which -std=c11 hides
// unless a feature-test macro is defined (glibc needs this; macOS and OpenBSD
// expose them by default)
#define _DEFAULT_SOURCE

#include "lua.h"
#include "lauxlib.h"

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/time.h>
#include <math.h>

static lua_State *lastL;
static lua_Number backprop;
static lua_Number rate;
static const char *skipsource;

// Arm a one-shot real-time timer. ITIMER_REAL has fine enough resolution to
// honor the sampling rate, unlike ITIMER_PROF, which only ticks with the kernel
static inline void randomalarm(void)
{
    // Exponential decay:
    int r = rand();
    useconds_t delay = (useconds_t)(-log((double)r/(double)RAND_MAX) * 1e3 / rate);
    struct itimerval timer;
    memset(&timer, 0, sizeof(timer));
    timer.it_value.tv_sec = (time_t)((1 + delay) / 1000000);
    timer.it_value.tv_usec = (suseconds_t)((1 + delay) % 1000000);
    setitimer(ITIMER_REAL, &timer, NULL);
}

static inline void disarmtimer(void)
{
    struct itimerval timer;
    memset(&timer, 0, sizeof(timer));
    setitimer(ITIMER_REAL, &timer, NULL);
}

static inline void bump(lua_State *L, lua_Debug *ar, lua_Number amount)
{
    int profile_index = lua_gettop(L);
    lua_getinfo(L, "lS", ar);
    lua_pushfstring(L, "%s:%d", ar->short_src, ar->currentline);
    int key_index = lua_gettop(L);
    lua_pushvalue(L, key_index);
    int type = lua_gettable(L, profile_index);
    if (type == LUA_TNIL) {
        lua_pop(L, 1);
        lua_pushnumber(L, amount);
    } else {
        lua_Number count = lua_tonumber(L, -1);
        count += amount;
        lua_pop(L, 1);
        lua_pushnumber(L, count);
    }
    lua_settable(L, profile_index);
}

static void ltakesample(lua_State *L, lua_Debug *ar)
{
    lua_Debug ar2;
    lua_getstack(L, 0, &ar2);
    lua_getinfo(L, "S", &ar2);
    // A return from a Lua function means the signal landed in Lua code, so
    // wait for the next line rather than sampling the return point
    if (ar->event == LUA_HOOKRET && strcmp(ar2.what, "C") != 0)
        return;

    lua_pushlightuserdata(L, &lastL);
    lua_gettable(L, LUA_REGISTRYINDEX);

    lua_Number weight = 1.0;
    int top = 1;
    for (int level = 0; lua_getstack(L, level, &ar2); level++) {
        lua_getinfo(L, "S", &ar2);
        if (skipsource && strcmp(ar2.source, skipsource) == 0)
            continue;
        // Time spent in a C function is charged to the Lua line that called
        // it, so skip any C frames at the top of the stack
        if (top && strcmp(ar2.what, "C") == 0)
            continue;
        top = 0;
        bump(L, &ar2, weight);
        weight *= backprop;
    }
    // Disable hook and set alarm
    lua_sethook(lastL, NULL, 0, 0);
    randomalarm();
}

static void handler(int sig)
{
    (void)sig;
    if (lastL)
        lua_sethook(lastL, ltakesample, LUA_MASKLINE | LUA_MASKRET, 0);
}

static int Lcollect(lua_State *L)
{
    // The source string stays on the stack for the whole call, so the pointer
    // remains valid until we return
    const char *new_skipsource = luaL_checkstring(L, 1);
    lua_Number new_backprop = luaL_checknumber(L, 2);
    lua_Number new_rate = luaL_checknumber(L, 3);
    luaL_checktype(L, 4, LUA_TFUNCTION);
    skipsource = new_skipsource;
    backprop = new_backprop;
    rate = new_rate;

    // Start each call with a fresh results table
    lua_pushlightuserdata(L, &lastL);
    lua_createtable(L, 0, 128);
    lua_settable(L, LUA_REGISTRYINDEX);

    // lastL must be set before the timer is armed: if the first alarm fired
    // while it was still NULL, the handler would do nothing, the timer would
    // never be re-armed, and the whole call would get no samples
    lastL = L;

    struct sigaction newaction, oldaction;
    memset(&newaction, 0, sizeof(newaction));
    newaction.sa_handler = handler;
    newaction.sa_flags = SA_NODEFER;
    sigaction(SIGALRM, &newaction, &oldaction);
    randomalarm();

    // Call `fn` (argument 4) with everything above it
    int status = lua_pcall(L, lua_gettop(L) - 4, 0, 0);

    // Ignore SIGALRM and cancel the timer before removing the hook, so a
    // signal that is still in flight can't re-install the hook afterward
    newaction.sa_handler = SIG_IGN;
    sigaction(SIGALRM, &newaction, NULL);
    disarmtimer();
    lua_sethook(L, NULL, 0, 0);
    sigaction(SIGALRM, &oldaction, NULL);
    lastL = NULL;
    skipsource = NULL;

    if (status != LUA_OK)
        return lua_error(L);

    lua_pushlightuserdata(L, &lastL);
    lua_gettable(L, LUA_REGISTRYINDEX);

    return 1;
}

LUALIB_API int luaopen_sampleprof_core(lua_State *L);
LUALIB_API int luaopen_sampleprof_core(lua_State *L)
{
    static const luaL_Reg functions[] = {
        {"collect", Lcollect},
        {NULL, NULL},
    };
    luaL_newlib(L, functions);
    return 1;
}
