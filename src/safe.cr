module Sync
  # Types with this annotation explicitly state that they are safe to be
  # accessed from any `Fiber` in any `Fiber::ExecutionContext` synchronously or
  # asynchronously.
  #
  # For example they can be used as globals, such as constants or class
  # variables, or for closured variables shared with multiple fibers at once.
  #
  # A linter can then use this annotation to determine when a shared variable is
  # safe or not.
  annotation Safe
  end
end
