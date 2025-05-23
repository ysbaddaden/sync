require "./lockable"
require "./rw_lock"

module Sync
  # Safely share a value `T` across fibers and execution contexts using a
  # `RWLock` to control when the access to a value can be shared (read-only) or
  # must be exclusive (replace or mutate the value).
  #
  # For example:
  #
  # ```
  # require "sync/shared"
  #
  # class Queue
  #   @@running : Sync::Shared.new([] of Queue)
  #
  #   def self.on_started(queue)
  #     @@running.write(&.push(queue))
  #   end
  #
  #   def self.on_stopped(queue)
  #     @@running.write(&.delete(queue))
  #   end
  #
  #   def self.each(&)
  #     @@running.read do |list|
  #       list.each { |queue| yield queue }
  #     end
  #   end
  # end
  # ```
  #
  # Consider a `Shared(T)` if your workload mostly consists of immutable reads
  # of the value, with only seldom writes or inner mutations of the value's
  # inner state.
  @[Sync::Safe]
  class Shared(T)
    include Lockable

    def initialize(@value : T, type : Type = :checked)
      @lock = uninitialized ReferenceStorage(RWLock)
      RWLock.unsafe_construct(pointerof(@lock), type)
    end

    private def lock : RWLock
      @lock.to_reference
    end

    # Locks in shared mode and yields the value. The lock is released before
    # returning.
    #
    # The value is owned in shared mode for the duration of the block, and thus
    # shouldn't be mutated for example, unless `T` can be safely mutated (it
    # should be `Sync::Safe`).
    #
    # WARNING: The value musn't be retained and accessed after the block has
    # returned.
    def read(& : T -> U) : U forall U
      lock.read { yield @value }
    end

    # Locks in exclusive mode and yields the value. The lock is released before
    # returning.
    #
    # The value is owned in exclusive mode for the duration of the block, as
    # such it can be safely mutated.
    #
    # WARNING: The value musn't be retained and accessed after the block has
    # returned.
    def write(& : T -> U) : U forall U
      lock.write { yield @value }
    end

    # Locks in exclusive mode, yields the current value and eventually replaces
    # the value with the one returned by the block. The lock is released before
    # returning.
    #
    # The current value is now owned: it can be safely retained and mutated even
    # after the block returned.
    #
    # WARNING: The new value musn't be retained and accessed after the block has
    # returned.
    def replace(& : T -> T) : Nil
      lock.write { @value = yield @value }
    end

    # Locks in shared mode and returns a shallow copy of the value. The lock is
    # released before returning the new value.
    #
    # Sometimes it may not be needed to own or borrow the value (no need to
    # mutate it, or the value is returned by copy anyway), and taking a copy can
    # help release the lock early, instead of keeping the lock acquired for a
    # while, preventing progress of fibers trying to lock exclusively.
    #
    # @[Experimental("The method may not have much value over #read(&.dup)")]
    def dup_value : T
      lock.read { @value.dup }
    end

    # Locks in shared mode and returns a deep copy of the value. The lock is
    # released before returning the new value.
    #
    # @[Experimental("The method may not have much value over #read(&.clone)")]
    def clone_value : T
      lock.read { @value.clone }
    end

    # Locks in shared mode and returns the value. Unlocks before returning.
    #
    # Always acquires the lock, so reading the value is synchronized in relation
    # with the other methods. However, safely accessing the returned value
    # entirely depends on the safety of `T`, which should be `Sync::Safe`.
    #
    # Prefer `#dup_value` or `#clone_value` to get a shallow or deep copy of the
    # value instead.
    #
    # WARNING: Breaks the shared/exclusive guarantees since the returned value
    # outlives the lock, the value can be accessed concurrently to the
    # synchronized methods.
    #
    # @[Experimental("The method may not have much value over #read(&.itself)")]
    def value : T
      lock.read { @value }
    end

    # Locks in exclusive mode and sets the value.
    def set(value : T) : Nil
      lock.write { @value = value }
    end

    # Returns the value without any synchronization.
    #
    # WARNING: Breaks the safety constraints! Only use when you can guarantee
    # that the current fiber acquired the lock or to access a value that can be
    # read in a single load operation from memory.
    def unsafe_get : T
      @value
    end

    # Sets the value without any synchronization.
    #
    # WARNING: Breaks the safety constraints! Only use when you can guarantee
    # that the current fiber acquired the lock or to access a value that can be
    # written in a single store operation into memory.
    def unsafe_set(@value : T) : T
    end

    protected def wait(cv : Pointer(CV)) : Nil
      lock.wait(cv)
    end
  end
end
