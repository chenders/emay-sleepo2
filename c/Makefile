CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -O2
SRC     = src/emay_sleepo2.c
TEST    = tests/test_main.c

.PHONY: all test clean

all: build/libemay_sleepo2.a

build:
	mkdir -p build

build/emay_sleepo2.o: $(SRC) | build
	$(CC) $(CFLAGS) -c $< -o $@ 2>&1 || \
		(echo "NOTE: BLE deps (libdbus) may be missing — protocol-only build" && \
		 $(CC) $(CFLAGS) -DEMAY_NO_BLE -c $< -o $@)

build/libemay_sleepo2.a: build/emay_sleepo2.o
	ar rcs $@ $^

test: build/libemay_sleepo2.a
	$(CC) $(CFLAGS) -Isrc $(TEST) -Lbuild -lemay_sleepo2 -o build/test_main && ./build/test_main

clean:
	rm -rf build
