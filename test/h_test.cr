require "./test_helper"
require "../src/h"

class Sync::HTest < Minitest::Test
  def test_put
    h = H(Int32, Int32).new(16)
    assert_equal 0, h.size

    # insert
    assert h.put(1, 1.hash, 123)
    assert_equal 1, h.size

    assert h.put(5, 5.hash, 54)
    assert h.put(129879, 129879.hash, 789)
    assert_equal 3, h.size
    assert_equal 54, h.fetch(5, 5.hash) { nil }

    # replace key
    refute h.put(5, 5.hash, 79)
    assert_equal 3, h.size
    assert_equal 79, h.fetch(5, 5.hash) { nil }
  end

  def test_delete
    h = H(Int32, Int32).new(16)
    assert_equal 0, h.size

    # delete unknown key
    _, success = h.delete(1, 1.hash)
    refute success

    assert h.put(1, 1.hash, 123)
    assert h.put(5, 5.hash, 54)
    assert h.put(129879, 129879.hash, 789)

    # delete known key
    value, success = h.delete(5, 5.hash)
    assert success
    assert_equal 54, value
    assert_equal 2, h.size
    assert_nil h.fetch(5, 5.hash) { nil }

    # reinsert (recycle tombstone)
    assert h.put(5, 5.hash, 88)
    assert_equal 3, h.size
    assert_equal 88, h.fetch(5, 5.hash) { nil }
  end

  def test_resizes
    h = H(Int32, Int32).new(8)

    # insert
    2048.times do |i|
      h.put(i, i.hash, i * 2)
    end
    assert_equal 2048, h.size
    assert_equal 4096, h.capacity

    # verify
    2048.times do |i|
      assert_equal i * 2, h.fetch(i, i.hash) { nil }
    end

    # delete half the keys (even ones)
    1024.times do |i|
      j = i * 2
      h.delete(j, j.hash)
    end
    assert_equal 1024, h.size
    assert_equal 2048, h.capacity

    # verify
    1.step(to: 2047, by: 2) do |i|
      assert_equal i * 2, h.fetch(i, i.hash) { nil }
    end

    # re-insert + replace existing
    2048.times do |i|
      h.put(i, i.hash, i * 3)
    end

    # verify
    2048.times do |i|
      assert_equal i * 3, h.fetch(i, i.hash) { nil }
    end

    assert_equal 2048, h.size
    assert_equal 4096, h.capacity
  end
end
