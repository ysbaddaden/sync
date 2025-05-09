require "./test_helper"
require "../src/dll"

class Sync::DllTest < Minitest::Test
  struct Foo
    include Dll::Node

    getter value : Int32

    def initialize(@value : Int32)
    end
  end

  def test_init
    a = Foo.init(1)
    b = Foo.init(1)

    assert a.is_a?(Pointer(Foo))

    assert_equal a, a.value.prev
    assert_equal a, a.value.next

    refute_equal a, b.value.prev
    refute_equal a, b.value.next
  end

  def test_empty?
    list = Dll(Foo).new
    assert list.empty?

    a = Foo.init(1)
    list.push(a)
    refute list.empty?

    list.delete(a)
    assert list.empty?
  end

  def test_push
    a = Foo.init(1)
    b = Foo.init(2)
    c = Foo.init(3)
    d = Foo.init(4)
    e = Foo.init(5)
    f = Foo.init(6)

    list = Dll(Foo).new

    # insert first node
    list.push(a)
    assert_equal a, list.first?
    assert_equal a, list.last?
    assert_null list.next?(a)
    assert_null list.prev?(a)

    # append another node
    list.push(b)

    assert_equal a, list.first?
    assert_equal b, list.last?

    assert_null list.prev?(a)
    assert_null list.next?(b)

    assert_equal b, list.next?(a)
    assert_equal a, list.prev?(b)

    # append more nodes
    list.push(c)
    list.push(d)
    list.push(e)
    list.push(f)

    assert_equal a, list.first?
    assert_equal f, list.last?

    assert_null list.prev?(a)
    assert_null list.next?(f)

    assert_equal b, list.next?(a)
    assert_equal c, list.next?(b)
    assert_equal d, list.next?(c)
    assert_equal e, list.next?(d)
    assert_equal f, list.next?(e)

    assert_equal a, list.prev?(b)
    assert_equal b, list.prev?(c)
    assert_equal c, list.prev?(d)
    assert_equal d, list.prev?(e)
    assert_equal e, list.prev?(f)
  end

  def test_unshift
    a = Foo.init(1)
    b = Foo.init(2)
    c = Foo.init(3)
    d = Foo.init(4)
    e = Foo.init(5)
    f = Foo.init(6)

    list = Dll(Foo).new

    # insert first node
    list.unshift(a)
    assert_equal a, list.first?
    assert_equal a, list.last?
    assert_null list.next?(a)
    assert_null list.prev?(a)

    # prepend another node
    list.unshift(b)

    assert_equal b, list.first?
    assert_equal a, list.last?

    assert_null list.prev?(b)
    assert_null list.next?(a)

    assert_equal a, list.next?(b)
    assert_equal b, list.prev?(a)

    # prepend more nodes
    list.unshift(c)
    list.unshift(d)
    list.unshift(e)
    list.unshift(f)

    assert_equal f, list.first?
    assert_equal a, list.last?

    assert_null list.prev?(f)
    assert_null list.next?(a)

    assert_equal e, list.next?(f)
    assert_equal d, list.next?(e)
    assert_equal c, list.next?(d)
    assert_equal b, list.next?(c)
    assert_equal a, list.next?(b)

    assert_equal f, list.prev?(e)
    assert_equal e, list.prev?(d)
    assert_equal d, list.prev?(c)
    assert_equal c, list.prev?(b)
    assert_equal b, list.prev?(a)
  end

  def test_shift?
    a = Foo.init(1)
    b = Foo.init(2)
    c = Foo.init(3)
    d = Foo.init(4)
    e = Foo.init(5)
    f = Foo.init(6)

    list = Dll(Foo).new
    assert_null list.shift?

    list.push(a)
    list.push(b)
    list.push(c)
    list.push(d)
    list.push(e)
    list.push(f)

    assert_equal a, list.shift?
    assert_equal a, a.value.next
    assert_equal a, a.value.prev

    assert_equal b, list.shift?
    assert_equal c, list.shift?
    assert_equal d, list.shift?
    assert_equal e, list.shift?
    assert_equal f, list.shift?
    assert_null list.shift?
  end

  def test_pop?
    a = Foo.init(1)
    b = Foo.init(2)
    c = Foo.init(3)
    d = Foo.init(4)
    e = Foo.init(5)
    f = Foo.init(6)

    list = Dll(Foo).new
    assert_null list.pop?

    list.push(a)
    list.push(b)
    list.push(c)
    list.push(d)
    list.push(e)
    list.push(f)

    assert_equal f, list.pop?
    assert_equal f, f.value.next
    assert_equal f, f.value.prev

    assert_equal e, list.pop?
    assert_equal d, list.pop?
    assert_equal c, list.pop?
    assert_equal b, list.pop?
    assert_equal a, list.pop?
    assert_null list.pop?
  end

  def test_delete?
    a = Foo.init(1)
    b = Foo.init(2)
    c = Foo.init(3)
    d = Foo.init(4)
    e = Foo.init(5)
    f = Foo.init(6)

    list = Dll(Foo).new

    # remove node not in list has no effect
    list.delete(a)
    assert_equal a, a.value.next
    assert_equal a, a.value.prev

    list.push(a)
    list.push(b)
    list.push(c)
    list.push(d)
    list.push(e)
    list.push(f)

    # remove inner node
    list.delete(c)
    assert_equal c, c.value.next
    assert_equal c, c.value.prev

    # remove another node and the tail
    list.delete(d)
    list.delete(f)

    assert_equal a, list.shift?
    assert_equal b, list.shift?
    assert_equal e, list.shift?
    assert_null list.shift?
  end

  def test_each
    a = Foo.init(1)
    b = Foo.init(2)
    c = Foo.init(3)
    d = Foo.init(4)
    e = Foo.init(5)
    f = Foo.init(6)

    list = Dll(Foo).new

    # iterate empty list
    called = 0
    list.each { called += 1 }
    assert_equal 0, called

    list.push(a)
    list.push(b)
    list.push(c)
    list.push(d)
    list.push(e)
    list.push(f)

    # iterate all items
    2.times do
      ary = [a, b, c, d, e, f]
      list.each { |node| assert_equal ary.shift?, node }
      assert_empty ary
    end

    # can delete node while iterating
    ary = [a, b, c, d, e, f]
    list.each do |node|
      assert_equal ary.shift?, node
      list.delete(node) if ary.size.odd?
    end

    ary = [b, d, f]
    list.each { |node| assert_equal ary.shift?, node }
    assert_empty ary
  end

  def test_each
    a = Foo.init(1)
    b = Foo.init(2)
    c = Foo.init(3)
    d = Foo.init(4)
    e = Foo.init(5)
    f = Foo.init(6)

    list = Dll(Foo).new

    # consume empty list
    called = 0
    list.consume_each { called += 1 }
    assert_equal 0, called

    list.push(a)
    list.push(b)
    list.push(c)
    list.push(d)
    list.push(e)
    list.push(f)

    ary = [a, b, c, d, e, f]
    list.consume_each do |node|
      assert_equal ary.shift?, node
      assert_equal node, node.value.next
      assert_equal node, node.value.prev
    end
    assert_empty ary

    called = 0
    list.consume_each { called += 1 }
    assert_equal 0, called
  end

  private def assert_null(actual)
    assert_equal Pointer(Foo).null, actual
  end
end
