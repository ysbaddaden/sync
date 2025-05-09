.POSIX:
.PHONY:

CRYSTAL = crystal
CRFLAGS =
TESTS = test/*_test.cr
OPTS = --parallel 4

-include local.mk

all:

test: .PHONY
	$(CRYSTAL) run $(CRFLAGS) -Dpreview_mt $(TESTS) -- $(OPTS)

bench/%: bench/%.cr src/*.cr src/**/*.cr
	$(CRYSTAL) build $(CRFLAGS) -Dpreview_mt --release $< -o $@

docs: .PHONY
	$(CRYSTAL) docs src/sync.cr
