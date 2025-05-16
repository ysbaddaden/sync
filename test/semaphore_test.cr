require "./test_helper"
require "../src/semaphore"

class Sync::SemaphoreTest < Minitest::Test
  def test_scenario
    # only 5 fibers can do something at the same time
    semaphore = Sync::Semaphore.new(5)
    run = Atomic(Int32).new(0)
    counter = Atomic(Int32).new(0)

    ready = WaitGroup.new(1)
    step = WaitGroup.new(1)

    WaitGroup.wait do |wg|
      9.times do
        wg.spawn do
          run.add(1, :relaxed)
          ready.wait

          semaphore.acquire
          counter.add(1, :relaxed)

          step.wait
          semaphore.release
        end
      end

      # wait for fibers to be started
      eventually { assert_equal 9, run.get(:relaxed) }
      ready.done

      # no more than 5 fibers can progress
      eventually { assert_equal 5, counter.get(:relaxed) }
      10.times do
        assert_equal 5, counter.get(:relaxed)
        Fiber.yield
      end

      # tell the fibers to release the semaphore, so another batch can progress
      step.done
      eventually { assert_equal 9, counter.get(:relaxed) }
    end
  end
end
