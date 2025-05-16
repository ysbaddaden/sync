require "./dll"
require "./safe"
require "./waiter"

module Sync
  # Counting semaphore.
  #
  # Allows a limited number of fibers to enter a critical section at a time.
  #
  # In the following example, only 4 fibers can compute a password hash
  # concurrently. If the server has more than 4 CPU cores then only 4 threads
  # may be blocked hashing a password, while the other threads will keep
  # processing requests.
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
  @[Sync::Safe]
  struct Semaphore
    def initialize(value : Int32)
      @value = Atomic(Int32).new(value)
      @mu = MU.new
      @waiters = Dll(Waiter).new
    end

    def value : Int32
      @value.get(:relaxed)
    end

    def synchronize(& : -> U) : U forall U
      wait
      begin
        yield
      ensure
        signal
      end
    end

    # Decrements the semaphore. Blocks the calling fiber if the new value is
    # negative, otherwise returns immediately (consumed an unit).
    def wait : Nil
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
    def signal : Nil
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
