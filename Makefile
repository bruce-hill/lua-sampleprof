# makefile for sampleprof library for Lua

LUA_DIR=/usr/local
LUA_INC= $(LUA_DIR)/include
LUA_BIN= $(LUA_DIR)/bin
LUA= lua

CC= gcc
CFLAGS= $(INCS) $(WARN) -O3 $G
WARN= -std=c11 -pedantic -Wall -Wextra
INCS= -I$(LUA_INC)
#MAKESO= $(CC) $(CFLAGS) -shared
MAKESO= $(CC) $(CFLAGS) -bundle -undefined dynamic_lookup

MYNAME= sampleprof
MYLIB= l$(MYNAME)
T= $(MYNAME).so
OBJS= $(MYLIB).o
TEST= test.lua

all: $T

.PHONY: test
test: $T
	$(LUA_BIN)/$(LUA) $(TEST)

o:	$(MYLIB).o

so:	$T

$T:	$(OBJS)
	$(MAKESO) -o $@ $(OBJS)

$(OBJS): $(MYLIB).c

clean:
	rm -f $(OBJS) $T

# eof
