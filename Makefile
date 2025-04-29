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

docs: .PHONY
	$(CRYSTAL) docs src/sync.cr
