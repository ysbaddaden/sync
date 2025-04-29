require "minitest/autorun"
require "wait_group"

class Minitest::Test
  protected def eventually(timeout : Time::Span = 5.seconds, &)
    start = Time.monotonic

    loop do
      Fiber.yield

      begin
        yield
      rescue ex
        raise ex if (Time.monotonic - start) > timeout
      else
        break
      end
    end
  end

  protected def async(&block) : Nil
    done = false
    exception = nil

    spawn do
      block.call
    rescue ex
      exception = ex
    ensure
      done = true
    end

    eventually { assert done, "Expected async fiber to have finished" }

    if ex = exception
      raise ex
    end
  end
end
