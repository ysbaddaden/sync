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

bench/map: bench/map.cr src/*.cr
	$(CRYSTAL) build $(CRFLAGS) --release $< -o $@

bench/map_run: bench/map .PHONY
	$(CRYSTAL) bench/map_run.cr > bench/map.dat
	gnuplot bench/map.plot

bench/%: bench/%.cr src/*.cr
	$(CRYSTAL) build $(CRFLAGS) --release $< -o $@

bench/%_sync: bench/%.cr src/*.cr
	$(CRYSTAL) build $(CRFLAGS) -DSYNC --release $< -o $@

docs: .PHONY
	$(CRYSTAL) docs src/sync.cr

clean: .PHONY
	rm -f bench/map bench/mutex bench/mutex_sync bench/mu_lock bench/mu_rlock bench/mu_rwlock
