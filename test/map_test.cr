require "./test_helper"
require "../src/map"

class Sync::MapTest < Minitest::Test
  def test_put
    map = Map(Int32, Int32).new(16, 4)
    assert_equal 0, map.size

    # insert
    assert_equal 123, map[1] = 123
    assert_equal 1, map.size

    assert_equal 54, map[5] = 54
    assert_equal 789, map[129879] = 789
    assert_equal 3, map.size
    assert_equal 54, map[5]

    # replace key
    assert_equal 79, map[5] = 79
    assert_equal 3, map.size
    assert_equal 79, map[5]
  end

  def test_update
    map = Map(Int32, Int32).new(16, 4)
    assert_raises(KeyError) { map.update(1) { |v| v * 2 } }

    map[1] = 3
    assert_equal 3, map.update(1) { |v| v * 2 }
    assert_equal 6, map[1]
  end

  def test_put_if_absent
    map = Map(Int32, Int32).new(16, 4)

    assert_equal 64, map.put_if_absent(1, 64)
    assert_equal 1, map.size

    5.times do |i|
      assert_equal 64, map.put_if_absent(1, i)
      assert_equal 1, map.size
    end

    assert_equal 256, map.put_if_absent(2, 256)
    assert_equal 2, map.size

    assert_equal 64, map[1]
    assert_equal 256, map[2]
  end

  def test_fetch
    map = Map(Int32, Int32).new(16, 4)
    map[1] = 123
    map[-5] = 54
    map[129879] = 789

    # raising
    assert_equal 123, map[1]
    assert_equal 54, map[-5]
    assert_raises(KeyError) { map[2] }

    # nilable
    assert_equal 123, map[1]?
    assert_equal 54, map[-5]?
    assert_nil map[2]?

    # default
    assert_equal 123, map.fetch(1, -1)
    assert_equal 789, map.fetch(129879, -2)
    assert_equal -3, map.fetch(2, -3)
    assert_nil map.fetch(2, nil)

    # default (block)
    assert_equal 123, map.fetch(1) { -1 }
    assert_equal 789, map.fetch(129879) { -2 }
    assert_equal 981726, map.fetch(2) { 981726 }
  end

  def test_has_key?
    map = Map(Int32, Int32).new(16, 4)
    refute map.has_key?(1)

    map[1] = 123
    map[-5] = 54
    map[129879] = 789

    assert map.has_key?(1)
    assert map.has_key?(-5)
    assert map.has_key?(129879)
    refute map.has_key?(0)
    refute map.has_key?(9812)
  end

  def test_each
    map = Map(Int32, Int32).new(16, 4)
    100.times { |i| map[i * 2] = i * 5 }

    keys = [] of Int32
    values = [] of Int32

    map.each do |k, v|
      keys << k
      values << v
    end

    assert_equal 100.times.map(&.*(2)).to_a, keys.sort!
    assert_equal 100.times.map(&.*(5)).to_a, values.sort!
  end

  def test_keys
    map = Map(Int32, Int32).new(16, 4)
    assert_equal [] of Int32, map.keys

    map[1] = 123
    map[-5] = 54
    map[129879] = 789
    assert_equal [-5, 1, 129879], map.keys.sort!
  end

  def test_values
    map = Map(Int32, Int32).new(16, 4)
    assert_equal [] of Int32, map.values

    map[1] = 123
    map[-5] = 54
    map[129879] = 789
    assert_equal [54, 123, 789], map.values.sort!
  end

  def test_delete
    map = Map(Int32, Int32).new(16, 4)
    assert_equal 0, map.size

    # delete unknown key
    assert_nil map.delete(1)

    map[1] = 123
    map[5] = 54
    map[129879] = 789

    # delete known key
    assert_equal 54, map.delete(5)
    assert_equal 2, map.size
    assert_nil map[5]?

    # reinsert (recycle tombstone)
    map[5] = 88
    assert_equal 3, map.size
    assert_equal 88, map[5]
  end

  def test_resizes
    map = Map(Int32, Int32).new(8, 4)
    wg = WaitGroup.new

    # insert
    WaitGroup.wait do |wg|
      8.times do |n|
        wg.spawn do
          256.times do |i|
            ii = n * 256 + i
            map[ii] = ii * 2
          end
        end
      end
    end
    assert_equal 2048, map.size

    # verify
    WaitGroup.wait do |wg|
      8.times do |n|
        256.times do |i|
          ii = n * 256 + i
          assert_equal ii * 2, map[ii]
        end
      end
    end

    # delete half the keys (even ones)
    WaitGroup.wait do |wg|
      8.times do |n|
        128.times do |i|
          j = (n * 128 + i) * 2
          map.delete(j)
        end
      end
    end
    assert_equal 1024, map.size

    # verify
    1.step(to: 2047, by: 2) do |i|
      assert_equal i * 2, map[i]
    end

    # re-insert + replace existing
    WaitGroup.wait do |wg|
      8.times do |n|
        wg.spawn do
          256.times do |i|
            ii = n * 256 + i
            map[ii] = ii * 3
          end
        end
      end
    end

    # verify
    2048.times do |i|
      assert_equal i * 3, map[i]
    end
    assert_equal 2048, map.size
  end

  def test_rehash
    skip
  end

  def test_dup
    map = Map(Int32, Int32).new(16, 4)
    map[1] = 123
    map[-5] = 54
    map[129879] = 789

    copy = map.dup
    refute_same map, copy
    assert_equal map.to_a, copy.to_a
    assert_equal map.size, copy.size

    # modifying copy doesn't affect original
    copy[1] = 321
    copy[2] = 4
    refute_equal map.to_a.sort!, copy.to_a.sort!
  end

  def test_clear
    skip
  end
end
