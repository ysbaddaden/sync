.POSIX:
.PHONY:

CRYSTAL = crystal
CRFLAGS =
TESTS = test/*_test.cr
OPTS = --parallel 4

-include local.mk

all:

test: .PHONY
	$(CRYSTAL) run $(CRFLAGS) $(TESTS) -- $(OPTS)

bench/%: bench/%.cr src/*.cr src/**/*.cr
	$(CRYSTAL) build $(CRFLAGS) --release $< -o $@

docs: .PHONY
	$(CRYSTAL) docs src/sync.cr
