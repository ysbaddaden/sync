require "../src/mu"
require "wait_group"

mt = Fiber::ExecutionContext::MultiThreaded.new("MT", Fiber::ExecutionContext.default_workers_count)
g = WaitGroup.new(1)

c = ENV.fetch("C", "10").to_u64(underscore: true)
n = ENV.fetch("N", "10_000_000").to_u64(underscore: true)
m = n // c

counter = 0_u64
mu = Sync::MU.new

mt.spawn do
  WaitGroup.wait do |wg|
    c.times do
      wg.spawn do
        m.times do |i|
          mu.lock
          counter += 1
          # Fiber.yield if i % 100 == 99
          mu.unlock
          # Fiber.yield if i % 100 == 99
        end
      end
    end
  end
ensure
  g.done
end

g.wait
exit (counter == c * m) ? 0 : 1
