/*
* lsampleprof.c
* A Lua sample profiling library by Bruce Hill. This library returns a single
* function of the form profile([backprop=.619, [rate=100]], fn, ...)
* that runs `fn` with any extra args, performs sample profiling, and
* returns a table of the results.
*
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

#define DEFAULT_BACKPROP 0.619
#define DEFAULT_RATE 100

static lua_State *lastL;
static lua_Number backprop = DEFAULT_BACKPROP;
static lua_Number rate = DEFAULT_RATE;

// Arm a one-shot timer that counts CPU time used by this process, so that
// time spent blocked (I/O, sleep) isn't sampled
static inline void randomalarm(void)
{
    // Exponential decay:
    int r = rand();
    useconds_t delay = (useconds_t)(-log((double)r/(double)RAND_MAX) * 1e3 / rate);
    struct itimerval timer;
    memset(&timer, 0, sizeof(timer));
    timer.it_value.tv_sec = (time_t)((1 + delay) / 1000000);
    timer.it_value.tv_usec = (suseconds_t)((1 + delay) % 1000000);
    setitimer(ITIMER_PROF, &timer, NULL);
}

static inline void disarmtimer(void)
{
    struct itimerval timer;
    memset(&timer, 0, sizeof(timer));
    setitimer(ITIMER_PROF, &timer, NULL);
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
    lua_pushlightuserdata(L, &lastL);
    lua_gettable(L, LUA_REGISTRYINDEX);

    lua_Number weight = 1.0;
    bump(L, ar, weight);
    lua_Debug ar2;
    // Level 0 is the current frame, already tallied above, so start at 1
    for (int i = 1; lua_getstack(L, i, &ar2); i++) {
        weight *= backprop;
        bump(L, &ar2, weight);
    }
    // Disable hook and set alarm
    lua_sethook(lastL, NULL, 0, 0);
    randomalarm();
}

static void handler(int sig)
{
    (void)sig;
    if (lastL)
        lua_sethook(lastL, ltakesample, LUA_MASKLINE, 0);
}

static int Lwrap(lua_State *L)
{
    // Backprop
    if (lua_type(L, 1) == LUA_TNUMBER) {
        backprop = lua_tonumber(L, 1);
        lua_remove(L, 1);
    }
    // Sampling rate
    if (lua_type(L, 1) == LUA_TNUMBER) {
        rate = lua_tonumber(L, 1);
        lua_remove(L, 1);
    }

    struct sigaction newaction, oldaction;
    memset(&newaction, 0, sizeof(newaction));
    newaction.sa_handler = handler;
    newaction.sa_flags = SA_NODEFER;
    sigaction(SIGPROF, &newaction, &oldaction);
    randomalarm();

    // Start each call with a fresh results table
    lua_pushlightuserdata(L, &lastL);
    lua_createtable(L, 0, 128);
    lua_settable(L, LUA_REGISTRYINDEX);

    lastL = L;
    int status = lua_pcall(L, lua_gettop(L)-1, 0, 0);

    // Ignore SIGPROF and cancel the timer before removing the hook, so a
    // signal that is still in flight can't re-install the hook afterward
    newaction.sa_handler = SIG_IGN;
    sigaction(SIGPROF, &newaction, NULL);
    disarmtimer();
    lua_sethook(L, NULL, 0, 0);
    sigaction(SIGPROF, &oldaction, NULL);
    lastL = NULL;

    backprop = DEFAULT_BACKPROP;
    rate = DEFAULT_RATE;

    if (status != LUA_OK)
        return lua_error(L);

    lua_pushlightuserdata(L, &lastL);
    lua_gettable(L, LUA_REGISTRYINDEX);

    return 1;
}

LUALIB_API int luaopen_sampleprof(lua_State *L);
LUALIB_API int luaopen_sampleprof(lua_State *L)
{
    lua_pushcfunction(L, Lwrap);
    return 1;
}
