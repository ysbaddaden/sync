require "./mu"

module Sync
  module Lockable
    enum Type
      # The lock doesn't do any checks. Trying to relock will cause a deadlock,
      # unlocking from any fiber is undefined behavior.
      Unchecked

      # The lock checks whether the current fiber owns the lock. Trying to
      # relock will raise a `Error::Deadlock` exception, unlocking when unlocked
      # or while another fiber holds the lock will raise an `Error`.
      Checked

      # Same as `Checked` with the difference that the lock allows the same
      # fiber to re-lock as many times as needed, then must be unlocked as many
      # times as it was re-locked.
      Reentrant
    end

    protected abstract def type : Type
    protected abstract def locked_by? : Fiber?
    protected abstract def locked_by=(locked_by : Fiber?) # : Fiber?
    protected abstract def counter : Int32
    protected abstract def counter=(counter : Int32) # : Int32
    protected abstract def owns_lock? : Bool
    protected abstract def mu : Pointer(MU)
  end
end
