require "./test_helper"
require "../src/once"

class Sync::OnceTest < Minitest::Test
  def test_call
    called = 0

    once = Once(Int32).new do
      sleep(10.milliseconds)
      called += 1
      2736
    end

    WaitGroup.wait do |wg|
      10.times do
        wg.spawn do
          assert_equal 2736, once.call
        end
      end
    end

    assert_equal 1, called
  end

  def test_call_raises
    called = 0

    once = Once(Int32).new do
      called += 1
      sleep(10.milliseconds)
      Int32::MAX + 1
    end

    WaitGroup.wait do |wg|
      10.times do
        wg.spawn do
          assert_raises(OverflowError) { once.call }
        end
      end
    end

    assert_equal 1, called
  end
end
