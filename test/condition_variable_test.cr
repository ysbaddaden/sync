require "./test_helper"
require "../src/mutex"
require "../src/condition_variable"

class Sync::ConditionVariableTest < Minitest::Test
  def test_signal
    m = Sync::Mutex.new
    c = Sync::ConditionVariable.new(m)

    m.synchronize do
      spawn do
        m.synchronize { c.signal }
      end

      c.wait
    end
  end

  def test_signal_mutex
    m = Sync::Mutex.new
    c = Sync::ConditionVariable.new(m)
    done = waiting = 0
    n = 100

    n.times do
      ::spawn do
        m.synchronize do
          waiting += 1
          c.wait
          done += 1
        end
      end
    end
    eventually { assert_equal n, waiting }

    # resume fibers one by one
    n.times do |i|
      eventually { assert_equal i, done }
      c.signal
      Fiber.yield
    end

    eventually { assert_equal n, done }
  end

  def test_signal_rwlock
    l = Sync::RWLock.new
    c = Sync::ConditionVariable.new(l)

    r = 50
    w = 10
    done = waiting = 0

    r.times do
      ::spawn do
        until done == w
          l.read { c.wait }
        end
      end
    end

    w.times do
      ::spawn do
        l.write do
          waiting += 1
          c.wait
          done += 1
        end
      end
    end

    eventually { assert_equal w, waiting }

    # resumes at most one reader per signal
    w.times do |i|
      eventually { assert_equal i, done }
      c.signal
      Fiber.yield
    end

    # wake any pending readers
    c.broadcast
  end

  def test_broadcast_mutex
    m = Sync::Mutex.new
    c = Sync::ConditionVariable.new(m)
    done = waiting = 0

    100.times do
      ::spawn do
        m.synchronize do
          waiting += 1
          c.wait
          done += 1
        end
      end
    end
    eventually { assert_equal 100, waiting }
    assert_equal 0, done

    # resume all fibers at once
    c.broadcast
    eventually { assert_equal 100, done }
  end

  def test_broadcast_rwlock
    l = Sync::RWLock.new
    c = Sync::ConditionVariable.new(l)
    done = waiting = 0
    r = 50
    w = 100

    r.times do
      ::spawn do
        until done == w
          l.read { c.wait }
        end
      end
    end

    w.times do
      ::spawn do
        l.write do
          waiting += 1
          c.wait
          done += 1
        end
      end
    end
    eventually { assert_equal w, waiting }
    assert_equal 0, done

    # resume all fibers at once
    c.broadcast
    eventually { assert_equal w, done }

    # wake any pending readers
    c.broadcast
  end

  def test_producer_consumer
    m = Sync::Mutex.new
    c = Sync::ConditionVariable.new(m)

    state = -1
    ready = false

    ::spawn(name: "cv:consumer") do
      m.synchronize do
        ready = true
        c.wait
        assert_equal 1, state
        state = 2
      end
    end

    ::spawn(name: "cv:producer") do
      eventually { assert ready, "expected consumer to eventually be ready" }
      m.synchronize { state = 1 }
      c.signal
    end

    eventually { assert_equal 2, state }
  end

  def test_reentrant_mutex
    m = Sync::Mutex.new(:reentrant)
    c = Sync::ConditionVariable.new(m)

    m.lock
    m.lock

    spawn do
      m.lock
      c.signal
      m.unlock
    end

    c.wait

    m.unlock
    m.unlock # musn't raise (can't unlock Sync::Mutex that isn't locked)
  end

  def test_reentrant_rwlock
    m = Sync::RWLock.new(:reentrant)
    c = Sync::ConditionVariable.new(m)

    m.lock_write
    m.lock_write

    spawn do
      m.lock_write
      c.signal
      m.unlock_write
    end

    c.wait

    m.unlock_write
    m.unlock_write # musn't raise (can't unlock Sync::RWLock that isn't locked)
  end
end
