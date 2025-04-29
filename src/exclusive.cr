require "./mutex"

module Sync
  # Safely share a value `T` across fibers and execution contexts using a
  # `Mutex`, so only one critical section can access the value at any time.
  #
  # For example:
  #
  # ```
  # require "sync/exclusive"
  #
  # class Queue
  #   @@running : Sync::Exclusive.new([] of Queue)
  #
  #   def self.on_started(queue)
  #     @@running.get(&.push(queue))
  #   end
  #
  #   def self.on_stopped(queue)
  #     @@running.get(&.delete(queue))
  #   end
  #
  #   def self.each(&)
  #     @@running.get do |list|
  #       list.each { |queue| yield queue }
  #     end
  #   end
  # end
  # ```
  @[Sync::Safe]
  class Exclusive(T)
    def initialize(@value : T, type : Mutex::Type = :checked)
      @lock = uninitialized ReferenceStorage(Mutex)
      Mutex.unsafe_construct(pointerof(@lock), type)
    end

    private def lock : Mutex
      @lock.to_reference
    end

    # Locks the mutex and yields the value. The lock is released before
    # returning.
    #
    # The value is owned for the duration of the block, and can be safely
    # mutated for example.
    #
    # WARNING: The value musn't be retained and accessed after the block has
    # returned.
    def get(& : T -> U) : U forall U
      lock.synchronize { yield @value }
    end

    # Locks the mutex, yields the value and eventually replaces the value with
    # the one returned by the block. The lock is released before returning.
    #
    # The yielded value is owned: it can be safely mutated and even retained
    # after the block returned.
    #
    # WARNING: The new value musn't be retained and accessed after the block has
    # returned.
    def replace(& : T -> T) : T
      lock.synchronize { @value = yield @value }
    end

    # Locks the mutex and returns a shallow copy of the value. The lock is
    # released before returning the new value.
    def dup : T
      lock.synchronize { @value.dup }
    end

    # Locks the mutex and returns a deep copy of the value. The lock is
    # released before returning the new value.
    def clone : T
      lock.synchronize { @value.clone }
    end

    # Locks the mutex and returns the value. Unlocks the mutex before returning.
    #
    # Always acquires the lock, so reading the value is synchronized in relation
    # with the other methods. However, safely accessing the returned value
    # entirely depends on the safety of `T`, which should be `Sync::Safe`.
    #
    # Prefer `#dup` or `#clone` to get a shallow or deep copy of the value
    # instead.
    #
    # WARNING: Breaks the mutual exclusion guarantee, since the returned value
    # outlives the lock it can be accessed in parallel to the synchronized
    # methods.
    def get : T
      lock.synchronize { @value }
    end

    # Locks the mutex and sets the value. Unlocks the mutex before returning.
    #
    # Always acquires and releases the lock, so writing the value is always
    # synchronized with the other methods.
    def set(value : T) : T forall T
      lock.synchronize { @value = value }
    end

    # Returns the value without any synchronization.
    #
    # WARNING: Breaks the mutual exclusion constraint. Only use when you can
    # guarantee that the current fiber acquired the lock or to access a value
    # that can be read in a single load operation from memory.
    def unsafe_get : T
      @value
    end

    # Sets the value without any synchronization.
    #
    # WARNING: Breaks the mutual exclusion constraint. Only use when you can
    # guarantee that the current fiber acquired the lock or to access a value
    # that can be written in a single store operation into memory.
    def unsafe_set(@value : T) : T
    end
  end
end
