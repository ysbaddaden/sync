require "crystal/spin_lock"
require "./core_ext/pointer_linked_list"
require "./mu"

module Sync
  # :nodoc:
  #
  # The building block for condition variables.
  #
  # OPTIMIZE: implement nsync's cv algorithm
  @[Sync::Safe]
  struct CV
    def initialize
      @waiting = Crystal::PointerLinkedList(Fiber::PointerLinkedListNode).new
      @spin = Crystal::SpinLock.new
    end

    # NOTE: assumes that the current fiber locked *mu*
    def wait(mu : Pointer(MU)) : Nil
      waiter = Fiber::PointerLinkedListNode.new(Fiber.current)

      @spin.lock
      @waiting.push pointerof(waiter)
      @spin.unlock

      mu.value.unlock
      Fiber.suspend
      mu.value.lock
    end

    def signal : Nil
      @spin.lock
      waiter = @waiting.shift?
      @spin.unlock

      waiter.value.enqueue if waiter
    end

    def broadcast : Nil
      @spin.lock
      waiting = @waiting
      @waiting.clear
      @spin.unlock

      waiting.each(&.value.enqueue)
    end
  end
end
