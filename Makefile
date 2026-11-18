# makefile for sampleprof library for Lua

UNAME_S:= $(shell uname -s)

# Lua headers and interpreter. Override on the command line if needed, e.g.
#   make LUA_INC=/usr/include/lua5.4
ifeq ($(UNAME_S),Linux)
LUA_DIR?= /usr
else
LUA_DIR?= /usr/local
endif
LUA_INC?= $(LUA_DIR)/include
LUA_BIN?= $(LUA_DIR)/bin
LUA?= lua
MOON?= moon

CC?= cc
INCS= -I$(LUA_INC)

# Warnings are kept to what gcc and clang both understand, so the same flags
# work on Linux, macOS, and OpenBSD. -Werror is deliberately not included;
# add it locally with `make WERROR=-Werror`
WARN= -std=c11 -pedantic -Wall -Wextra -Wformat=2 -Wshadow \
	-Wconversion -Wsign-conversion -Wdouble-promotion \
	-Wcast-align -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes \
	-Wold-style-definition -Wundef -Wimplicit-fallthrough -Wvla \
	-Wjump-misses-init $(WERROR)
CFLAGS= $(INCS) $(WARN) -fPIC -O3 $G
LDLIBS= -lm

ifeq ($(UNAME_S),Darwin)
MAKESO= $(CC) $(CFLAGS) -bundle -undefined dynamic_lookup
else
MAKESO= $(CC) $(CFLAGS) -shared
endif

MYNAME= sampleprof
MYLIB= l$(MYNAME)
T= $(MYNAME)_core.so
OBJS= $(MYLIB).o
TEST= test.lua
TEST_MOON= test_moon.moon

all: $T

.PHONY: test test-moon
test: $T
	$(LUA_BIN)/$(LUA) $(TEST)

# Requires MoonScript
test-moon: $T
	$(MOON) $(TEST_MOON)

o:	$(MYLIB).o

so:	$T

$T:	$(OBJS)
	$(MAKESO) -o $@ $(OBJS) $(LDLIBS)

$(OBJS): $(MYLIB).c

clean:
	rm -f $(OBJS) $T

# eof
