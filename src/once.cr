require "./future"
require "./safe"

module Sync
  # An object to execute an operation once. For example lazily initialize
  # objects, such as database connections or loading configuration.
  #
  # For example:
  #
  # ```
  # SETTINGS = Sync::Once(Hash(String, String)).new do
  #   parse_settings
  # end
  #
  # 10.times do
  #   spawn do
  #     settings = SETTINGS.call
  #     # ...
  #   end
  # end
  # ```
  @[Sync::Safe]
  class Once(T)
    def initialize(&@block : -> T)
      @flag = Atomic(Bool).new(false)
      @future = uninitialized ReferenceStorage(Future(T))
      Future(T).unsafe_construct(pointerof(@future))
    end

    # Executes the block once.
    #
    # In the case of multiple concurrent calls, all but the first call will
    # execute the block, the other calling fibers will block until the first
    # fiber finished executing the block. Following calls will immediately
    # return the result.
    #
    # If the block raises an exception, all concurrent and following calls will
    # re-raise the exception. A failure won't cause the block to be called
    # again.
    def call : T
      if @flag.swap(true, :relaxed)
        @future.to_reference.get
      else
        call_impl
      end
    end

    private def call_impl
      value = @block.call
      @future.to_reference.set(value)
      value
    rescue ex
      @future.to_reference.fail(ex)
      raise ex
    end
  end
end
