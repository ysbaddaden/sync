require "./test_helper"
require "../src/mutex"
require "../src/rw_lock"
require "../src/condition_variable"

describe Sync::ReentrantTest do
  it "Mutex: counter should be restored correctly after `cv.value.wait pointerof(@mu)`" do
    m = Sync::Mutex.new(type: :reentrant)
    c = Sync::ConditionVariable.new(m)

    chan = Channel(String).new

    exception = nil

    spawn do
      m.synchronize do
        # puts "f1 lock"
        m.synchronize do
          # puts "f1 reentrant and cv.wait"
          c.wait
        ensure
          # puts "f1 unlock reentrant"
        end
      ensure
        # puts "f1 unlock"
      end
    rescue ex
      exception = ex
    ensure
      chan.send("f1")
    end

    spawn do
      m.synchronize do # will reset counter to 1 here
        # puts "f2 lock"
        assert true
      ensure
        # puts "f2 unlock"
      end
    rescue ex
      exception = ex
    ensure
      chan.send("f2")
    end

    assert_equal "f2", chan.receive # waitfor f2
    c.signal                        # signal f1
    assert_equal "f1", chan.receive # waitfor f1
    if ex = exception
      raise ex
    end
  end

  it "RWLock: counter should be restored correctly after `cv.value.wait pointerof(@mu)`" do
    m = Sync::RWLock.new(type: :reentrant)
    c = Sync::ConditionVariable.new(m)

    chan = Channel(String).new

    exception = nil

    spawn do
      m.write do
        # puts "f1 lock"
        m.write do
          # puts "f1 reentrant and cv.wait"
          c.wait
        ensure
          # puts "f1 unlock reentrant"
        end
      ensure
        # puts "f1 unlock"
      end
    rescue ex
      exception = ex
    ensure
      chan.send("f1")
    end

    spawn do
      m.write do # will reset counter to 1 here
        # puts "f2 lock"
        assert true
      ensure
        # puts "f2 unlock"
      end
    rescue ex
      exception = ex
    ensure
      chan.send("f2")
    end

    assert_equal "f2", chan.receive # waitfor f2
    c.signal                        # signal f1
    assert_equal "f1", chan.receive # waitfor f1
    if ex = exception
      raise ex
    end
  end
end
