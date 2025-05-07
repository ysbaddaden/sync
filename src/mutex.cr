require "./errors"
require "./mu"

module Sync
  # A mutual exclusion lock to protect critical sections.
  #
  # A single fiber can acquire the lock at a time. No other fiber can acquire
  # the lock while a fiber holds it.
  #
  # This lock can for example be used to protect the access to some resources,
  # with the guarantee that only one section of code can ever read, write or
  # mutate said resources.
  #
  # NOTE: Consider `Exclusive(T)` to protect a value `T` with a `Mutex`.
  @[Sync::Safe]
  class Mutex
    enum Type
      # The mutex doesn't do any checks. Trying to relock will cause a deadlock,
      # unlocking from any fiber is undefined behavior.
      Unchecked

      # The mutex checks whether the current fiber owns the lock. Trying to
      # relock will raise a `Error::Deadlock` exception, unlocking when unlocked
      # or while another fiber holds the lock will raise an `Error`.
      Checked

      # Same as `Checked` with the difference that the mutex allows the same
      # fiber to re-lock as many times as needed, then must be unlocked as many
      # times as it was re-locked.
      Reentrant
    end

    def initialize(@type : Type = :checked)
      @counter = 0
      @mu = MU.new
    end

    # Acquires the exclusive lock for the duration of the block. The lock will
    # be released automatically before returning, or if the block raises an
    # exception.
    def synchronize(& : -> U) : U forall U
      lock
      begin
        yield
      ensure
        unlock
      end
    end

    # Acquires the exclusive lock.
    def lock : Nil
      unless @mu.try_lock?
        unless @type.unchecked?
          if @locked_by == Fiber.current
            raise Error::Deadlock.new unless @type.reentrant?
            @counter += 1
            return
          end
        end
        @mu.lock_slow
      end

      unless @type.unchecked?
        @locked_by = Fiber.current
        @counter = 1 if @type.reentrant?
      end
    end

    # Releases the exclusive lock.
    def unlock : Nil
      unless @type.unchecked?
        owns_lock!

        if @type.reentrant?
          return unless (@counter -= 1) == 0
        end
        @locked_by = nil
      end
      @mu.unlock
    end

    protected def owns_lock! : Nil
      if (fiber = @locked_by) == Fiber.current
        return
      end

      message = fiber ?
        "Can't unlock a mutex locked by another fiber" :
        "Can't unlock a mutex that isn't locked"
      raise Error.new(message)
    end
  end
end
