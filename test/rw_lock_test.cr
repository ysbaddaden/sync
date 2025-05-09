require "./test_helper"
require "../src/rw_lock"

describe Sync::RWLock do
  it "lock write waits for all read locks to be unlocked" do
    done = false

    lock = Sync::RWLock.new
    lock.lock_read
    lock.lock_read

    spawn do
      lock.lock_write
      done = true
    end

    sleep(10.milliseconds)
    refute done

    lock.unlock_read
    sleep(10.milliseconds)
    refute done

    lock.unlock_read
    sleep(10.milliseconds)
    assert done
  end

  it "can't lock read while locked for write" do
    done = false

    lock = Sync::RWLock.new
    lock.lock_write

    spawn do
      lock.lock_read
      done = true
    end

    sleep(10.milliseconds)
    refute done

    lock.unlock_write
    sleep(10.milliseconds)
    assert done
  end

  it "synchronizes locks" do
    lock = Sync::RWLock.new
    wg = WaitGroup.new

    ary = [] of Int32
    counter = Atomic(Int64).new(0)

    # readers can run concurrently, but are mutually exclusive to writers (the
    # array can be safely read from):

    10.times do
      spawn(name: "reader") do
        100.times do
          lock.read do
            ary.each { counter.add(1) }
          end
          Fiber.yield
        end
      end
    end

    # writers are mutually exclusive: they can safely mutate the array

    5.times do
      wg.spawn(name: "writer:increment") do
        100.times do
          lock.write { 100.times { ary << ary.size } }
          Fiber.yield
        end
      end
    end

    4.times do
      wg.spawn(name: "writer:decrement") do
        100.times do
          lock.write { 100.times { ary.pop? } }
          Fiber.yield
        end
      end
    end

    wg.wait

    assert_equal (0..(ary.size - 1)).to_a, ary
    assert counter.lazy_get > 0
  end

  describe "unchecked" do
    it "deadlocks on re-lock write" do
      done = started = locked = false
      lock = Sync::RWLock.new(:unchecked)

      fiber = spawn do
        started = true
        lock.lock_write
        locked = true
        lock.lock_write # deadlock
        raise "ERROR: unreachable" unless done
      end

      eventually { assert started }
      eventually { assert locked }
      sleep 10.milliseconds

      # unlock the fiber (cleanup)
      done = true
      lock.unlock_write
    end

    it "unlocks write despite not being locked" do
      lock = Sync::RWLock.new(:unchecked)
      assert_raises(RuntimeError) { lock.unlock_write } # MU has a safety check
    end

    it "unlocks write from another fiber" do
      lock = Sync::RWLock.new(:unchecked)
      lock.lock_write
      async { lock.unlock_write } # nothing raised
    end
  end

  describe "checked" do
    it "raises on re-kock write" do
      lock = Sync::RWLock.new(:checked)
      lock.lock_write
      assert_raises(Error::Deadlock) { lock.lock_write }
    end

    it "raises on unlock_write when not locked" do
      lock = Sync::RWLock.new(:checked)
      assert_raises(Error) { lock.unlock_write }
    end

    it "raises on unlock_write from another fiber" do
      lock = Sync::RWLock.new(:checked)
      lock.lock_write
      async do
        assert_raises(Error) { lock.unlock_write }
      end
    end
  end
end
