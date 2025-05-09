require "./dll"
require "./mu"
require "./safe"
require "./waiter"

module Sync
  # :nodoc:
  @[Sync::Safe]
  struct CV
    def initialize
      @word = Atomic(UInt32).new(0_u32)
      @waiters = Dll(Waiter).new
    end

    def wait(mu : Pointer(MU)) : Nil
      # TODO
    end

    def signal : Nil
      # TODO
    end

    def broadcast : Nil
      # TODO
    end
  end
end
