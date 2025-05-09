require "./dll"

module Sync
  # :nodoc:
  struct Waiter
    enum Type
      Reader
      Writer
    end

    include Dll::Node

    def initialize(@type : Type)
      # protects against spurious wakeups (invalid manual fiber enqueues) that
      # could lead to insert a waiter in the list a second time (oops) or keep
      # the waiter in the list while the caller returned
      @waiting = Atomic(Bool).new(true)
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

    def wait : Nil
      # OPTIMIZE: we could avoid suspending the fiber if @waiting is already
      # true but #wake ALWAYS enqueues the fiber, so #wait MUST suspend
      while true
        Fiber.suspend
        break unless @waiting.get(:relaxed)
      end
    end

    def wake : Nil
      @waiting.set(false, :relaxed)
      @fiber.enqueue
    end
  end
end
