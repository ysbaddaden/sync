.POSIX:
.PHONY:

CRYSTAL = crystal
CRFLAGS =
OPTS =

all:

test: .PHONY
	$(CRYSTAL) run -p -Dpreview_mt $(CRFLAGS) test/*_test.cr -- $(OPTS)

docs: .PHONY
	$(CRYSTAL) docs src/sync.cr
