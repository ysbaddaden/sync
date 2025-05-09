# Copyright 2023 Justine Alexandra Roberts Tunney
#
# Based on designs used by Mike Burrows and Linus Torvalds.
#
# Permission to use, copy, modify, and/or distribute this software for
# any purpose with or without fee is hereby granted, provided that the
# above copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
# WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
# AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
# DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
# PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
# TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

module Sync
  # :nodoc:
  struct Dll(T)
    module Node
      macro included
        property next : ::Pointer(self) = Pointer(self).null
        property prev : ::Pointer(self) = Pointer(self).null

        macro init(*args)
          \%node = ::{{@type}}.new(\{{args.splat}})
          ::Sync::Dll(::{{@type}}).init(pointerof(\%node))
          pointerof(\%node)
        end

        def alone? : Bool
          @next == @prev
        end
      end
    end

    # Nodes must be explicitly initialized to point to themselves, so they act
    # as a circular list with a single element. Since we include Node into
    # structs, we can't have the initializer do it automatically (the struct is
    # returned by copy, and the pointers become invalid).
    def self.init(node : Pointer(T)) : Nil
      node.value.next = node
      node.value.prev = node
    end

    # Points to the `Node` at the tail of the list.
    @list : Pointer(T) = Pointer(T).null

    def empty? : Bool
      @list.null?
    end

    # Returns the last node in the list. Returns a NULL pointer when empty.
    def last? : Pointer(T)
      @list
    end

    # Returns the first node in the list. Returns a NULL pointer when empty.
    def first? : Pointer(T)
      if list = @list
        list.value.next
      else
        Pointer(T).null
      end
    end

    # Returns the node that comes immediately after *node* in the list. Returns
    # a NULL pointer if *node* is the last node in the list.
    def next?(node : Pointer(T)) : Pointer(T)
      if node != @list
        node.value.next
      else
        Pointer(T).null
      end
    end

    # Returns the node that comes immediately before *node* in the list. Returns
    # a NULL pointer id *node* is the first node in the list.
    def prev?(node : Pointer(T)) : Pointer(T)
      if node != @list.value.next
        node.value.prev
      else
        Pointer(T).null
      end
    end

    # Yields each node in the list. The block owns the node; it can be deleted
    # from the list, for example, then inserted into another list.
    def each(& : Pointer(T) ->) : Nil
      node = first?

      while node
        next_ = next?(node)
        yield node
        node = next_
      end
    end

    # Removes and yields each node in the list. The block owns the node; it can
    # be inserted into another list, for example.
    def consume_each(& : Pointer(T) ->) : Nil
      while list = @list
        node = list.value.next
        delete(node)
        yield node
      end
    end

    # Removes *node* from the list.
    def delete(node : Pointer(T)) : Nil
      if @list == node
        if @list.value.prev == @list
          @list = Pointer(T).null
        else
          @list = @list.value.prev
        end
      end
      node.value.next.value.prev = node.value.prev
      node.value.prev.value.next = node.value.next
      node.value.next = node
      node.value.prev = node
    end

    # Removes and returns the last *node* from the list.
    def pop? : Pointer(T)
      if node = @list
        delete(node)
        node
      else
        Pointer(T).null
      end
    end

    # Removes and returns the first *node* from the list.
    def shift? : Pointer(T)
      if (list = @list) && (node = list.value.next)
        delete(node)
        node
      else
        Pointer(T).null
      end
    end

    # Inserts *node* into the list, at the beginning.
    def unshift(node : Pointer(T)) : Nil
      unless node.null?
        # raise "BUG: #{node} isn't in pristine state" unless node.value.alone?

        if @list.null?
          @list = node.value.prev
        else
          self.class.splice_after(@list, node)
        end
      end
    end

    # Inserts *node* into the list, at the end.
    def push(node : Pointer(T)) : Nil
      unless node.null?
        # raise "BUG: #{node} isn't in pristine state" unless node.value.alone?

        unshift(node.value.next)
        @list = node
      end
    end

    # Makes *succ* and its successors come after *node*.
    def self.splice_after(node : Pointer(T), succ : Pointer(T)) : Nil
      tmp1 = node.value.next
      tmp2 = succ.value.prev

      node.value.next = succ
      succ.value.prev = node

      tmp2.value.next = tmp1
      tmp1.value.prev = tmp2
    end
  end
end
