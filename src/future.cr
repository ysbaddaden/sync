require "./mu"
require "./errors"
require "./waiter"

module Sync
  # An object that will eventually hold a value.
  #
  # You can for example delegate the computation of a value to another fiber,
  # that can resolve is asynchronously, without blocking the current fiber, that
  # can regularly poll for the value, or explicitly wait until the value is
  # resolved.
  #
  # For example:
  #
  # ```
  # result = Future(Int32).new
  #
  # spawn do
  #   result.set(compute_some_value)
  # rescue exception
  #   result.fail(exception)
  # end
  #
  # loop do
  #   do_something
  #
  #   if value = result.get?
  #     p value
  #     break
  #   end
  # end
  # ```
  @[Sync::Safe]
  class Future(T)
    # :nodoc:
    enum State
      UNSET
      RESOLVED
      FAILED
    end

    @reason : Exception | String | Nil

    def initialize
      {% if (T.union? && T.union_types.any? { |t| t == Nil }) || T == Nil %}
        {% raise "Can't create Sync::Future for a nilable type" %}
      {% end %}
      @value = uninitialized T
      @mu = MU.new
      @state = State::UNSET
      @waiters = Dll(Waiter).new
    end

    # Sets the value, then wakes up pending fibers.
    #
    # Raises a `RuntimeError` if the future has already been resolved or has
    # already failed.
    def set(value : T) : T
      resolve(State::RESOLVED) { @value = value }
      value
    end

    # Sets the future as failed, then wakes up pending fibers.
    #
    # Raises a `RuntimeError` if the future has already been resolved or has
    # already failed.
    def fail(reason : Exception | String | Nil = nil) : Nil
      resolve(State::FAILED) { @reason = reason }
    end

    private def resolve(new_state, &)
      @mu.lock

      unless @state.unset?
        @mu.unlock
        raise RuntimeError.new("Can't resolve a future twice")
      end

      # we need an explicit fence for the compiler and weak cpu architectures
      # (e.g. ARM) to not reorder the memory stores, so any thread can safely
      # access the value, or the reason, depending on the observed state
      yield
      Atomic.fence(:acquire_release)
      @state = new_state

      @mu.unlock

      # @waiters is owned by the current fiber (neither #resolve nor #get will
      # try to access it anymore), we can safely iterate the list
      @waiters.consume_each(&.value.wake)
    end

    # Returns the value if resolved, otherwise returns `nil` immediately.
    # Raises an exception if the future has failed.
    def get? : T?
      case @state
      when State::RESOLVED
        @value
      when State::FAILED
        raise_exception!
      end
    end

    # Returns the value.
    # Blocks the current fiber until the future is resolved.
    # Raises an exception if the future has failed.
    def get : T
      loop do
        case @state
        when State::RESOLVED
          return @value
        when State::FAILED
          raise_exception!
        when State::UNSET
          waiter = Waiter.init(:reader)
          @mu.lock
          if @state.unset?
            @waiters.push(waiter)
            @mu.unlock
            waiter.value.wait
          else
            @mu.unlock
          end
        end
      end
    end

    private def raise_exception! : NoReturn
      case reason = @reason
      in Exception
        raise reason
      in String
        raise Error::Failed.new(reason)
      in Nil
        raise Error::Failed.new
      end
    end

    # :nodoc:
    def dup
      {% raise "Can't dup {{@type}}" %}
    end
  end
end
