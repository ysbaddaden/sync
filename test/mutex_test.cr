require "./test_helper"
require "../src/mutex"

describe Sync::Mutex do
  {% for type in %i[checked unchecked reentrant] %}
    describe {{type}} do
      it "locks and unlocks" do
        state = Atomic.new(0)
        m = Sync::Mutex.new({{type}})
        m.lock

        ::spawn do
          state.set(1)
          m.lock
          state.set(2)
        end

        eventually { assert_equal 1, state.get }
        m.unlock
        eventually { assert_equal 2, state.get }
      end

      {% unless type == :unchecked %}
        it "unlock raises when not locked" do
          m = Sync::Mutex.new({{type}})
          assert_raises(Sync::Error) { m.unlock }
        end

        it "unlock raises when another fiber tries to unlock" do
          m = Sync::Mutex.new(:reentrant)
          m.lock

          async do
            assert_raises(Sync::Error) { m.unlock }
          end
        end
      {% end %}

      it "synchronizes" do
        m = Sync::Mutex.new({{type}})
        counter = 0

        IO.pipe do |r, w|
          consumer = WaitGroup.new
          publishers = WaitGroup.new

          # no races when writing to pipe (concurrency)
          consumer.spawn do
            c = 0
            while line = r.gets
              assert_equal c += 1, line.to_i?
            end
          end

          # no races when incrementing counter (parallelism)
          100.times do |i|
            publishers.spawn do
              500.times do
                m.synchronize do
                  w.puts (counter += 1).to_s
                end
              end
            end
          end

          publishers.wait
          w.close
          assert_equal 100 * 500, counter

          consumer.wait
        end
      end
    end
  {% end %}

  describe "unchecked" do
    it "hangs on deadlock" do
      m = Sync::Mutex.new(:unchecked)
      done = started = locked = false

      fiber = ::spawn do
        started = true

        m.lock
        locked = true

        m.lock # deadlock
        raise "ERROR: unreachable" unless done
      end

      eventually { assert started }
      eventually { assert locked }
      sleep 10.milliseconds

      # unlock the fiber (cleanup)
      done = true
      m.unlock
    end

    it "unlocks from other fiber" do
      m = Sync::Mutex.new(:unchecked)
      m.lock
      async { m.unlock }
    end
  end

  describe "checked" do
    it "raises on deadlock" do
      m = Sync::Mutex.new(:checked)
      m.lock
      assert_raises(Sync::Deadlock) { m.lock }
    end
  end

  describe "reentrant" do
    it "re-locks" do
      m = Sync::Mutex.new(:reentrant)
      m.lock
      m.lock # nothing raised
    end

    it "unlocks as many times as it locked" do
      m = Sync::Mutex.new(:reentrant)
      100.times { m.lock }
      100.times { m.unlock }
      assert_raises(Sync::Error) { m.unlock }
    end
  end
end
