require "./test_helper"
require "../src/future"

describe Sync::Future do
  describe "#set" do
    it "resolves" do
      value = Sync::Future(Int32).new
      assert_equal 123, value.set(123)
    end

    it "can't resolve twice" do
      value = Sync::Future(Int32).new
      value.set(123)
      assert_raises(Sync::Error) { value.set(456) }
      assert_equal 123, value.get?
    end

    it "can't fail anymore" do
      value = Sync::Future(Int32).new
      value.set(321)
      assert_raises(Sync::Error) { value.fail(Exception.new) }
      assert_equal 321, value.get?
    end
  end

  describe "#fail" do
    it "fails with no reason" do
      value = Sync::Future(Int32).new
      value.fail
      ex = assert_raises(Failed) { value.get }
      assert_nil ex.message
    end

    it "fails with an string" do
      value = Sync::Future(Int32).new
      value.fail("can't compute the value")
      ex = assert_raises(Failed) { value.get }
      assert_equal "can't compute the value", ex.message
    end

    it "fails with an exception" do
      value = Sync::Future(Int32).new
      exception = Exception.new
      value.fail(exception)
      assert_same exception, assert_raises(Exception) { value.get }
    end

    it "can't fail twice" do
      value = Sync::Future(Int32).new
      exception = Exception.new

      value.fail(exception)
      assert_raises(Sync::Error) { value.fail(Exception.new) }

      raised_exception = assert_raises(Exception) { value.get }
      assert_same exception, raised_exception
    end

    it "can't resolve anymore" do
      value = Sync::Future(Int32).new
      exception = Exception.new

      value.fail(exception)
      assert_raises(Sync::Error) { value.set(123) }

      raised_exception = assert_raises(Exception) { value.get }
      assert_same exception, raised_exception
    end
  end

  describe "#get?" do
    it "returns the resolved value" do
      value = Sync::Future(Int32).new
      value.set(456)
      assert_equal 456, value.get?
    end

    it "doesn't block when unresolved" do
      value = Sync::Future(Int32).new
      assert_nil value.get?
    end

    it "raises when failed" do
      value = Sync::Future(Int32).new
      value.fail
      assert_raises(Sync::Failed) { value.get? }
    end
  end

  describe "#get" do
    it "returns the resolved value" do
      value = Sync::Future(Int32).new
      value.set(456)
      assert_equal 456, value.get?
    end

    it "blocks when unresolved" do
      ready = WaitGroup.new(100)
      counter = Atomic.new(0)

      value = Sync::Future(Int32).new
      result = nil

      100.times do
        spawn do
          ready.done

          result = value.get
          counter.add(1, :relaxed)
        end
      end

      spawn do
        ready.wait
        value.set(789)
      end

      eventually(1.seconds) { assert_equal 100, counter.get(:relaxed) }

      assert_equal 789, value.get
    end

    it "raises when failed" do
      value = Sync::Future(Int32).new
      value.fail
      assert_raises(Sync::Failed) { value.get? }
    end
  end
end

