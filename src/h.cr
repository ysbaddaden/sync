module Sync
  # :nodoc:
  #
  # Open addressing hash table with 2**n table size.
  # Uses quadratic probing in case of hash collision.
  # Lazy deletions.
  # Automatically grows when reaching 75% occupancy (used+deleted); rehashes
  # when deleted entries reach 25% occupancy, which might shrink the buffer.
  class H(K, V)
    private FREE = 0
    private ALLOCATED = 1
    private DELETED = 2

    MINSIZE = 4

    struct Entry(K, V)
      property status : Int32
      property key : K
      property value : V

      private def initialize(@key, @value)
        @status = FREE
      end

      protected def allocate(@key, @value) : Nil
        @status = ALLOCATED
      end

      protected def delete : V
        @status = DELETED
        value = @value
        # zero K and V, requires we only access them when status == ALLOCATED!
        LibIntrinsics.memset(pointerof(@key), 0, sizeof(K), false)
        LibIntrinsics.memset(pointerof(@value), 0, sizeof(V), false)
        value
      end
    end

    getter size : Int32
    protected setter size : Int32

    def initialize(initial_capacity : Int32)
      @entries = Pointer(Entry(K, V)).null
      @mask = 0_u32
      @size = 0
      @deleted = 0
      resize(initial_capacity)
    end

    def empty? : Bool
      @size == 0
    end

    def capacity : Int32
      (@mask + 1).to_i32
    end

    def each(& : (K, V) ->) : Nil
      return if empty?

      entry = @entries
      limit = @entries + capacity

      while entry < limit
        if entry.value.status == ALLOCATED
          yield entry.value.key, entry.value.value
        end
        entry += 1
      end
    end

    def fetch(key : K, hash : UInt64, & : -> U) : V | U forall U
      probe(hash) do |entry|
        case entry.value.status
        when FREE
          return yield
        when ALLOCATED
          return entry.value.value if entry.value.key == key
        end
      end
    end

    def put(key : K, hash : UInt64, value : V) : Bool
      entry = Pointer(Entry(K, V)).null
      added = false

      probe(hash) do |e|
        case e.value.status
        when FREE
          if (@size + @deleted) >= @mask - (@mask // 4)
            # reached 75% load, must grow or cleanup deleted entries
            resize(@size)
            entry = lookup_for_insert(key, hash)
          else
            # allocating e, or recycled entry
            entry ||= e
          end
          @size += 1
          added = true
          break
        when ALLOCATED
          if e.value.key == key
            unless entry
              # update existing entry
              e.value.value = value
              return false
            end
            # swap e with recycled entry (closer to perfect spot)
            e.value.delete
            break
          end
        when DELETED
          unless entry
            # recycle entry
            entry = e
            @deleted -= 1
            # must continue to iterate because the key may still be ALLOCATED
            # after this deleted entry, we must swap it with this one
          end
        end
      end

      entry.value.allocate(key, value)
      added
    end

    def update(key : K, hash : UInt64, & : V -> V) : V
      probe(hash) do |entry|
        case entry.value.status
        when FREE
          raise KeyError.new "Missing key: #{key.inspect}"
        when ALLOCATED
          if entry.value.key == key
            old_value = entry.value.value
            entry.value.value = yield old_value
            return old_value
          end
        end
      end
    end

    def delete(key : K, hash : UInt64) : {V, Bool}
      value = uninitialized V
      removed = false

      probe(hash) do |entry|
        case entry.value.status
        when FREE
          break
        when ALLOCATED
          if entry.value.key == key
            value = entry.value.delete
            removed = true
            @deleted &+= 1
            @size &-= 1
            # deleted entries reached 25% occupancy, must cleanup
            resize(@size) if @deleted >= (@mask &+ 1) // 4
            break
          end
        end
      end

      return {value, removed}
    end

    def clear : Nil
      raise NotImplementedError.new
    end

    def has_key?(key : K, hash : UInt64) : Bool
      probe(hash) do |entry|
        case entry.value.status
        when FREE
          return false
        when ALLOCATED
          return true if entry.value.key == key
        end
      end
    end

    def rehash : Nil
      resize(@size) unless empty?
    end

    private def resize(capacity)
      old_entries = @entries
      old_limit = old_entries + self.capacity

      # allocate new buffer
      if capacity < (2 ** 30 + 1)
        new_capacity = Math.pw2ceil(capacity.clamp(MINSIZE..))

        # double capacity if we'd reach over 75% capacity (on shrink)
        new_capacity *= 2 if @size >= new_capacity - new_capacity // 4
      else
        new_capacity = Int32::MAX
      end

      bytesize = sizeof(Entry(K, V)).to_u64 * new_capacity
      @entries = GC.malloc(bytesize).as(Pointer(Entry(K, V)))
      @mask = new_capacity.to_u32 &- 1

      return if old_entries.null?

      # reinsert entries into new buffer
      size = 0
      old_entry = old_entries

      while old_entry < old_limit
        if old_entry.value.status == ALLOCATED
          key = old_entry.value.key
          entry = lookup_for_insert(key, key.hash)
          entry.value.allocate(key, old_entry.value.value)
          size += 1
        end
        old_entry += 1
      end

      @size = size
      @deleted = 0

      # we can free the old hash
      GC.free(old_entries.as(Pointer(Void)))
    end

    private def lookup_for_insert(key, hash)
      probe(hash) do |entry|
        if entry.value.status != ALLOCATED || entry.value.key == key
          return entry
        end
      end
    end

    private def probe(i : UInt64, &)
      j = 1_u64
      while true
        entry = @entries + (i & @mask)
        yield entry
        i &+= (j &+= 1_u64)
      end
    end
  end
end
