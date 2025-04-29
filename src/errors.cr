module Sync
  # Raised when a sync check fails. For example when trying to unlock an
  # unlocked mutex, or trying to resolve a future twice. See `#message` for
  # details.
  class Error < Exception
  end

  # Raised when a lock would result in a deadlock. For example when trying to
  # re-lock a checked mutex.
  class Deadlock < Error
  end

  # Raised by `Future` when the future failed without an explicit exception.
  class Failed < Sync::Error
  end
end
