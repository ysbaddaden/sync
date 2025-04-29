require "crystal/spin_lock"
require "./core_ext/pointer_linked_list"
require "./safe"

module Sync
  # :nodoc:
  #
  # The fundation block for sync primitives (mutexes, rwlocks).
  #
  # OPTIMIZE: implement nsync's mu algorithm
  @[Sync::Safe]
  struct MU
    def initialize
      @waiting = Crystal::PointerLinkedList(Fiber::PointerLinkedListNode).new
      @spin = Crystal::SpinLock.new
      @m = Atomic(Bool).new(false)
    end

    def try_lock? : Bool
      @m.swap(true, :acquire) == false
    end

    def synchronize(&) : Nil
      lock
      begin
        yield
      ensure
        unlock
      end
    end

    def lock : Nil
      lock_slow unless try_lock?
    end

    def lock_slow : Nil
      waiter = Fiber::PointerLinkedListNode.new(Fiber.current)

      loop do
        @spin.lock

        # check again to avoid race condition with unlock
        if try_lock?
          @spin.unlock
          return
        end

        @waiting.push pointerof(waiter)
        @spin.unlock

        Fiber.suspend
      end
    end

    def unlock : Nil
      @m.set(false, :release)

      @spin.lock
      waiter = @waiting.shift?
      @spin.unlock

      waiter.value.enqueue if waiter
    end
  end
end
