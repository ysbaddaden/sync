# Crystal adaptation of "mu" from the "nsync" library with adaptations by
# Justine Alexandra Roberts Tunney in the "cosmopolitan" C library.
#
# Copyright 2016 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# References:
# - <https://github.com/google/nsync>
# - <https://github.com/jart/cosmopolitan/tree/master/third_party/nsync/>

require "./dll"
require "./mu"
require "./safe"
require "./waiter"

module Sync
  # :nodoc:
  @[Sync::Safe]
  struct CV
    SPINLOCK  = 1_u32
    NON_EMPTY = 2_u32

    def initialize
      @word = Atomic(UInt32).new(0_u32)
      @waiters = Dll(Waiter).new
    end

    def wait(mu : Pointer(MU), deadline : Time::Span? = nil) : Fiber::TimeoutResult
      waiter = Waiter.init(waiter_type(mu), mu)
      remove_count = waiter.value.remove_count # NOTE: always zero

      result = waiter.value.wait(deadline) { enqueue(mu, waiter) }
      outcome = resolve(waiter, remove_count, result)

      relock(mu, waiter) unless outcome.expired?
      outcome
    end

    private def enqueue(mu, waiter)
      waiter.value.waiting!

      old_word = acquire_spinlock(set: NON_EMPTY)
      @waiters.push(waiter)
      release_spinlock(old_word | NON_EMPTY)

      # release mu
      if waiter.value.writer?
        mu.value.unlock
      else
        mu.value.runlock
      end
    end

    private def resolve(waiter, remove_count, result)
      outcome = Fiber::TimeoutResult::CANCELED

      if result.expired? && waiter.value.waiting?
        must_suspend = false

        # timeout expired and no wakeup, confirm after acquiring spinlock
        old_word = acquire_spinlock
        if waiter.value.remove_count == remove_count # NOTE: waiter.value.zero? might be enough
          if waiter.value.waiting?
            # the waiter is still governed by this CV (not moved to a MU) and
            # still no wakeup
            outcome = Fiber::TimeoutResult::EXPIRED
            @waiters.delete(waiter)
            waiter.value.increment_remove_count
            old_word &= ~NON_EMPTY if @waiters.empty?
          end
        else
          # the waiter has been moved to a MU that will always enqueue the fiber
          # (the transfer erased the cancellation token)
          must_suspend = true
        end
        release_spinlock(old_word)

        Fiber.suspend if must_suspend
      end

      outcome
    end

    private def relock(mu, waiter)
      if waiter.value.cv_mu
        # waiter was woken from cv, and must re-acquire mu
        if waiter.value.writer?
          mu.value.lock
        else
          mu.value.rlock
        end
      else
        # waiter was moved to mu's queue, then awoken from mu and is thus a
        # designated waker, but it doesn't locked yet and must enter the lock
        # loop, and clear the DESIG_WAKER flag
        mu.value.lock_slow(waiter, clear: MU::DESIG_WAKER)
      end
    end

    def signal : Nil
      word = @word.get(:acquire)
      return if (word & NON_EMPTY) == 0

      wake = Dll(Waiter).new
      all_readers = false

      old_word = acquire_spinlock

      if first_waiter = @waiters.shift?
        first_waiter.value.increment_remove_count
        wake.push(first_waiter)

        if first_waiter.value.reader?
          # first waiter is a reader: wake all readers, and one writer (if any),
          # this allows all shared accesses to be resumed, while still allowing
          # only one exclusive access
          all_readers = true
          woke_writer = false

          @waiters.each do |waiter|
            if waiter.value.writer?
              next if woke_writer
              all_readers = false
              woke_writer = true
            end

            @waiters.delete(waiter)
            waiter.value.increment_remove_count
            wake.push(waiter)
          end
        end

        if @waiters.empty?
          old_word &= ~NON_EMPTY
        end
      end

      release_spinlock(old_word)

      wake_waiters pointerof(wake), all_readers
    end

    def broadcast : Nil
      word = @word.get(:acquire)
      return if (word & NON_EMPTY) == 0

      wake = Dll(Waiter).new
      all_readers = true

      old_word = acquire_spinlock

      # wake all waiters
      while waiter = @waiters.shift?
        all_readers = false if waiter.value.writer?
        waiter.value.increment_remove_count
        wake.push(waiter)
      end

      release_spinlock(old_word & ~NON_EMPTY)

      wake_waiters pointerof(wake), all_readers
    end

    private def wake_waiters(wake, all_readers)
      first_waiter = wake.value.first?
      return if first_waiter.null?

      if mu = first_waiter.value.cv_mu
        # try to transfer to mu's queue
        mu.value.try_transfer(wake, first_waiter, all_readers)
      end

      # wake waiters that didn't get transferred
      wake.value.consume_each(&.value.wake)
    end

    private def waiter_type(mu)
      is_writer = mu.value.held?
      is_reader = mu.value.rheld?

      if is_writer
        if is_reader
          raise "BUG: MU is held in reader and writer mode simultaneously on entry to CV#wait"
        end
        Waiter::Type::Writer
      elsif is_reader
        Waiter::Type::Reader
      else
        raise "BUG: MU not held on entry to CV#wait"
      end
    end

    private def acquire_spinlock(set = 0_u32, clear = 0_u32)
      attempts = 0

      while true
        word = @word.get(:relaxed)

        if (word & SPINLOCK) == 0
          _, success = @word.compare_and_set(word, (word | SPINLOCK | set) & ~clear, :acquire, :relaxed)
          return word if success
        end

        attempts = Thread.delay(attempts)
      end
    end

    private def release_spinlock(word)
      @word.set(word & ~SPINLOCK, :release)
    end
  end
end
