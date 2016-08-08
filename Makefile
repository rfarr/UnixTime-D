DMD=/usr/bin/env dmd
RELEASE_DFLAGS=-O -w -g -inline -release
LIB_DFLAGS=-lib
TEST_DFLAGS=-main -unittest -w -g
INCLUDES=-Isrc/

BUILD=builds/
SRCS=src/unixtime.d
EXAMPLES=examples/*.d

LIB_NAME=libunixtime
LIB=$(BUILD)$(LIB_NAME).a

TEST_NAME=unixtime_unittest
TEST=$(BUILD)$(TEST_NAME)

.PHONY: clean lib test

all: lib test

lib:
	$(DMD) -of$(LIB) $(INCLUDES) $(LIB_DFLAGS) $(RELEASE_DFLAGS) $(SRCS)

test:
	$(DMD) -of$(TEST) $(INCLUDES) $(TEST_DFLAGS) $(SRCS)
	$(TEST)

#examples: \
#	basic \
#	perf

#basic: lib
#	$(DMD) -of$(BUILD)basic $(INCLUDES) $(RELEASE_DFLAGS) examples/basic.d $(LIB)

#perf: lib
#	$(DMD) -of$(BUILD)perf $(INCLUDES) $(RELEASE_DFLAGS) examples/perf.d $(LIB)

clean:
	rm -rf $(BUILD)
