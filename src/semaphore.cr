require "./dll"
require "./safe"
require "./waiter"

module Sync
  # Counting semaphore.
  #
  # Allows a limited number of fibers to enter a critical section at a time.
  #
  # A counting semaphore can be a simple alternative to starting multiple
  # fibers, and requiring a `Channel` to pass work to execute, and maybe a
  # `Future` to get a value back. The semaphore is simpler, but starting
  # explicit fibers might prove better for your application, depending on your
  # workload.
  #
  # In the following example, only 4 fibers can compute a password hash
  # concurrently. If the computer has more than 4 CPU cores then only 4 threads
  # may be blocked hashing a password, while the other threads will keep running
  # the other fibers.
  #
  # ```
  # LOGINS = Sync::Semaphore.new(4)
  #
  # def hash(password)
  #   LOGINS.synchronize do
  #     Crypto::Bcrypt::Password.create("super secret", cost: 10)
  #   end
  # end
  # ```
  #
  # NOTE: A semaphore should have a value stricly greater than 1. Prefer a
  # `Mutex` if the concurrency of the critical section must be limited to one
  # exclusive fiber.
  @[Sync::Safe]
  struct Semaphore
    def initialize(value : Int32)
      @value = Atomic(Int32).new(value)
      @mu = MU.new
      @waiters = Dll(Waiter).new
    end

    # Returns the current value. Information only, the may be changed by the
    # time the method returns.
    def value : Int32
      @value.get(:relaxed)
    end

    # Acquires the semaphore, possibly blocking the calling fiber, then yields
    # the block and eventually releases the semaphore. Returns the value
    # returned by the block.
    def synchronize(& : -> U) : U forall U
      acquire
      begin
        yield
      ensure
        release
      end
    end

    # Decrements the semaphore. Blocks the calling fiber if the new value is
    # negative, otherwise returns immediately (consumed an unit).
    def acquire : Nil
      if @value.sub(1, :acquire_release) <= 0
        waiter = Waiter.init(:reader)

        @mu.lock
        waiter.value.waiting!
        @waiters.push(waiter)
        @mu.unlock

        waiter.value.wait
      end
    end

    # Increments the semaphore. Resumes a blocked fiber if the value was
    # negative.
    def release : Nil
      if @value.add(1, :acquire_release) < 0
        waiter = Pointer(Waiter).null

        @mu.lock
        waiter = @waiters.shift?
        @mu.unlock

        waiter.value.wake unless waiter.null?
      end
    end
  end
end
