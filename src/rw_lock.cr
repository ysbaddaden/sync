require "./mu"
require "./cv"
require "./errors"

module Sync
  # A multiple readers and exclusive writer lock to protect critical sections.
  #
  # Multiple fibers can acquire the shared lock (read) to allow some critical
  # sections to run concurrently. However a single fiber can acquire the
  # exclusive lock at a time to protect a single critical section to ever run in
  # parallel. When the lock has been acquired in exclusive mode, no other fiber
  # can lock it, be it in shared or exclusive mode.
  #
  # For example, the shared mode can allow to read one or many resources, albeit
  # the resources must be safe to be accessed in such manner, while the
  # exclusive mode allows to safely replace or mutate the resources with the
  # guarantee that nothing else is accessing said resources.
  #
  # The implementation doesn't favor readers or writers in particular.
  #
  # NOTE: Consider `Shared(T)` to protect a value `T` with a `RWLock`.
  @[Sync::Safe]
  class RWLock
    enum Type
      # The lock doesn't do any checks. Trying to relock will cause a deadlock,
      # unlocking from any fiber is undefined behavior.
      Unchecked

      # The lock checks whether the current fiber owns the lock. Trying to
      # relock will raise a `Error::Deadlock` exception, unlocking when unlocked
      # or while another fiber holds the lock will raise an `Error`.
      Checked

      # TODO: Reentrant
    end

    @locked_by : Fiber?

    def initialize(@type : Type = :checked)
      @mu = MU.new
      @cv = CV.new
      @readers = 0_u32
    end

    # Acquires the shared (read) lock for the duration of the block.
    #
    # Multiple fibers can acquire the shared (read) lock at the same time. The
    # block will never run concurrently to an exclusive (write) lock.
    def read(& : -> U) : U forall U
      lock_read
      begin
        yield
      ensure
        unlock_read
      end
    end

    # Acquires the shared (read) lock. The shared lock is always reentrant,
    # multiple fibers can lock it multiple times each, and never checked.
    # Blocks the calling fiber while the exclusive (write) lock is held.
    def lock_read : Nil
      @mu.synchronize do
        @readers += 1
      end
    end

    # Releases the shared (read) lock. Every fiber that locked must unlock to
    # actually release the reader lock, so a writer can lock for example. If a
    # fiber locked multiple times (reentrant) then it must unlock just as many
    # times.
    def unlock_read : Nil
      @mu.synchronize do
        if (@readers -= 1) == 0
          @cv.broadcast
        end
      end
    end

    # Acquires the exclusive (write) lock for the duration of the block.
    #
    # Only one fiber can acquire the exclusive (write) lock at the same time.
    # The block will never run concurrently to a shared (read) lock or another
    # exclusive (write) lock.
    def write(& : -> U) : U forall U
      lock_write
      begin
        yield
      ensure
        unlock_write
      end
    end

    # Acquires the exclusive (write) lock. Blocks the calling fiber while the
    # shared or exclusive (write) lock is held.
    def lock_write : Nil
      if @type.checked? && (@locked_by == Fiber.current)
        raise Error::Deadlock.new
      end

      @mu.lock

      until @readers == 0
        @cv.wait pointerof(@mu)
      end

      if @type.checked?
        @locked_by = Fiber.current
      end
    end

    # Releases the exclusive (write) lock.
    def unlock_write : Nil
      if @type.checked?
        owns_lock!
        @locked_by = nil
      end

      begin
        @cv.broadcast
      ensure
        @mu.unlock
      end
    end

    protected def owns_lock! : Nil
      if (fiber = @locked_by) == Fiber.current
        return
      end

      message = fiber ?
        "Can't unlock a rwlock locked by another fiber" :
        "Can't unlock a rwlock that isn't locked"
      raise Error.new(message)
    end
  end
end
