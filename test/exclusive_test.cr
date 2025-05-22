require "./test_helper"
require "../src/exclusive"

describe Sync::Exclusive do
  it "#get(&)" do
    ary = [1, 2, 3, 4, 5]
    var = Sync::Exclusive.new(ary)
    var.get { |val| assert_same ary, val }
  end

  it "#get" do
    ary = [1, 2, 3, 4, 5]
    var = Sync::Exclusive.new(ary)
    assert_same ary, var.get
  end

  it "#set" do
    ary1 = [1, 2, 3, 4, 5]
    ary2 = [4, 5, 8]

    var = Sync::Exclusive.new(ary1)
    var.set(ary2)
    assert_same ary2, var.get
  end

  it "#replace" do
    ary1 = [1, 2, 3, 4, 5]
    ary2 = [4, 5, 8]

    var = Sync::Exclusive.new(ary1)
    var.replace do |value|
      assert_same ary1, value
      ary2
    end
    assert_same ary2, var.get
  end

  it "#dup_value" do
    ary = [[1, 2, 3, 4, 5]]
    var = Sync::Exclusive.new(ary)

    copy = var.dup_value
    refute_same ary, copy
    assert_same ary[0], copy[0]
    assert_equal ary, copy
  end

  it "#clone_value" do
    ary = [[1, 2, 3, 4, 5]]
    var = Sync::Exclusive.new(ary)

    copy = var.clone_value
    refute_same ary, copy
    refute_same ary[0], copy[0]
    assert_equal ary, copy
  end

  it "#unsafe_get" do
    ary = [1, 2, 3, 4, 5]
    var = Sync::Exclusive.new(ary)
    assert_same ary, var.unsafe_get
  end

  it "#unsafe_set" do
    ary = [1, 2, 3, 4, 5]
    var = Sync::Exclusive.new(ary)
    assert_same ary, var.unsafe_get
  end

  private class Foo
    INSTANCE = Foo.new
    class_getter foo = Sync::Exclusive(Int64 | Foo).new(0_i64)
    @value = 123
  end

  it "synchronizes" do
    var = Sync::Exclusive.new([] of Int32)
    wg = WaitGroup.new

    counter = Atomic(Int64).new(0)

    10.times do
      spawn(name: "get") do
        100.times do
          var.get do |value|
            value.each { counter.add(1, :relaxed) }
          end
          Fiber.yield
        end
      end
    end

    5.times do
      wg.spawn(name: "get-mutates") do
        100.times do
          var.get do |value|
            100.times { value << value.size }
          end
          Fiber.yield
        end
      end
    end

    4.times do
      wg.spawn(name: "set-replace") do
        50.times do |i|
          if i % 2 == 1
            var.set([] of Int32)
          else
            var.replace { |value| value[0...10] }
          end
          Fiber.yield
        end
      end

      wg.spawn(name: "dup-clone") do
        100.times do |i|
          if i % 2 == 0
            var.dup_value
          else
            var.clone_value
          end
          Fiber.yield
        end
      end
    end

    wg.wait

    assert counter.get(:relaxed) > 0
  end

  {% if flag?(:execution_context) %}
    # see https://github.com/crystal-lang/crystal/issues/15085
    it "synchronizes reads/writes of mixed unions" do
      ready = WaitGroup.new(1)
      running = true

      # TODO: no need for wg after crystal 1.16.2 is released
      wg = WaitGroup.new(3)
      contexts = [] of Fiber::ExecutionContext::Isolated

      contexts << Fiber::ExecutionContext::Isolated.new("set:foo") do
        ready.wait
        while running
          Foo.foo.set(Foo::INSTANCE)
        end
      ensure
        wg.done
      end

      contexts << Fiber::ExecutionContext::Isolated.new("set:zero") do
        ready.wait
        while running
          Foo.foo.set(0_i64)
        end
      ensure
        wg.done
      end

      contexts << Fiber::ExecutionContext::Isolated.new("get") do
        ready.wait
        while running
          Foo.foo.get do |value|
            case value
            in Foo
              assert_equal Foo::INSTANCE.as(Void*).address, value.as(Void*).address
            in Int64
              assert_equal 0_i64, value
            end
          end
        end
      ensure
        wg.done
      end

      ready.done

      sleep 500.milliseconds
      running = false

      wg.wait
      contexts.each(&.wait)
    end
  {% end %}
end
