require "../src/mu"
require "wait_group"

mt = Fiber::ExecutionContext::MultiThreaded.new("MT", Fiber::ExecutionContext.default_workers_count)
g = WaitGroup.new(1)

c = ENV.fetch("C", "10").to_u64(underscore: true)         # how many readers
w = ENV.fetch("W", "2").to_u64(underscore: true)          # how many writers
n = ENV.fetch("N", "10_000_000").to_u64(underscore: true) # how many operations
m = n // c

counter = Atomic(UInt64).new(0)
done = Atomic(UInt64).new(0)
slice = Slice(UInt64).new(10) { |i| i.to_u64 }
mu = Sync::MU.new

mt.spawn do
  WaitGroup.wait do |wg|
    c.times do |j|
      wg.spawn(name: "r:#{j}") do
        LibC.dprintf 2, "r:%d > start\n", j

        m.times do |i|
          mu.rlock
          counter.add(slice.sample, :relaxed)
          mu.runlock
          Fiber.yield if i % 100 == 999
        end
      ensure
        LibC.dprintf 2, "r:%d > done\n", j
        done.add(1, :relaxed)
      end
    end

    w.times do |j|
      wg.spawn(name: "w:#{j}") do
        LibC.dprintf 2, "w:%d > start\n", j

        i = 0
        until done.get(:relaxed) == c
          mu.lock
          begin
            ptr = slice.to_unsafe
            if (i &+= 1) % 3 == 2
              LibC.dprintf 2, "w:%d > shrink\n", j
              size = slice.size // 3
              ptr = ptr.realloc(size.to_u64 * sizeof(UInt64)).as(UInt64*)
            else
              LibC.dprintf 2, "w:%d > grow\n", j
              size = slice.size * 2
              ptr = ptr.realloc(size.to_u64 * sizeof(UInt64)).as(UInt64*)
              (slice.size...size).each { |i| ptr[i] = i.to_u64 }
            end
            slice = Slice(UInt64).new(ptr, size)
          ensure
            mu.unlock
          end

          sleep 250.milliseconds
        end
      ensure
        LibC.dprintf 2, "w:%d > done\n", j
      end
    end
  end
ensure
  g.done
end

g.wait
p counter.get(:relaxed)

# exit (counter == c * m) ? 0 : 1
