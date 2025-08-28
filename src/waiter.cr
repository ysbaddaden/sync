require "./dll"
require "./mu"

module Sync
  # :nodoc:
  struct Waiter
    enum Type
      Reader
      Writer
    end

    include Dll::Node

    property cv_mu : Pointer(MU)
    setter cancellation_token : Fiber::CancellationToken?

    def initialize(@type : Type, @cv_mu : Pointer(MU) = Pointer(MU).null)
      # protects against spurious wakeups (invalid manual fiber enqueues) that
      # could lead to insert a waiter in the list a second time (oops) or keep
      # the waiter in the list while the caller returned
      @waiting = Atomic(Bool).new(true)
      @remove_count = Atomic(UInt32).new(0_u32)
      @fiber = Fiber.current
    end

    def reader? : Bool
      @type.reader?
    end

    def writer? : Bool
      @type.writer?
    end

    def waiting! : Nil
      @waiting.set(true, :relaxed)
    end

    def waiting? : Bool
      @waiting.get(:relaxed)
    end

    def remove_count : UInt32
      @remove_count.get(:relaxed)
    end

    def increment_remove_count : Nil
      @remove_count.add(1_u32, :relaxed)
    end

    def wait : Nil
      # we could avoid suspending the fiber if @waiting is already true but
      # #wake always enqueues the fiber, so #wait must suspend
      #
      # TODO: we likely don't need the loop (no spurious wakeup or cancellation)
      # or need to check @waiting (needed to resolve timeouts)
      while true
        Fiber.suspend
        break unless @waiting.get(:relaxed)
      end
    end

    def wait(deadline : Nil, &) : Fiber::TimeoutResult
      yield
      wait # TODO: Fiber.suspend is probably enough
      Fiber::TimeoutResult::CANCELED
    end

    def wait(deadline : Time::Span, &) : Fiber::TimeoutResult
      Fiber.sleep(until: deadline) do |cancellation_token|
        @cancellation_token = cancellation_token
        yield
      end
    end

    def wake : Nil
      @waiting.set(false, :relaxed)

      if token = @cancellation_token
        return unless Fiber.cancel_suspension?(token)
      end

      @fiber.enqueue
    end
  end
end
