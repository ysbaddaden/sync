require "./h"
require "./mu"
require "./safe"

module Sync
  # Safe and fast `Hash`-like data-structure.
  #
  # `Map` stores the key-value pairs in multiple buckets, each bucket being a
  # smaller map protected by its own rwlock, so only one bucket is locked at a
  # time, allowing other threads to keep interacting with the other buckets.
  #
  # With enough buckets per available parallelism of the CPU, thread contention
  # over a shared map is significantly reduced when compared to a single `Hash`
  # protected with a single `RWLock`, leading to huge performance improvements.
  #
  # The main drawback is large memory usage. By default the number of buckets is
  # 4 times the number of the system CPU count increased to the next power of
  # two, each with a minimum capacity of 4 entries. For example a 28-cores CPU
  # will create 128 buckets of 4 entries (1024 entries), and a `Map(String,
  # Float64)` will need at least 12KB of memory.
  #
  # Follows the `Hash` interface, but isn't a drop-in replacement.
  #
  # The main difference is that `Map` is unordered by design, while `Hash` is
  # ordered (key insertion is retained). For example iteration will yield
  # key-value pairs in unexpected order, and the map can't be sorted.
  #
  # The map is optimized for safe concurrent and parallel accesses of individual
  # entries. Methods that require to iterate, such as `#each`, `#keys`, or
  # `#values` will have to lock each bucket one after the other, and might not
  # fare that well.
  #
  # NOTE: If `K` overrides either `#==` or `#hash(hasher)` then both methods
  # must be overriden so that if two `K` are equal, then their hash must also be
  # equal (the opposite isn't true).
  @[Sync::Safe]
  class Map(K, V)
    private class Bucket(K, V)
      def initialize(initial_capacity : Int32)
        @mu = MU.new
        @h = H(K, V).new(initial_capacity)
      end

      def read(&)
        @mu.rlock
        begin
          yield
        ensure
          @mu.runlock
        end
      end

      def write(&)
        @mu.lock
        begin
          yield
        ensure
          @mu.unlock
        end
      end
    end

    def self.default_buckets_count : Int32
      Math.pw2ceil(System.cpu_count.to_i32.clamp(1..) * 4)
    end

    @buckets : Slice(Bucket(K, V))
    @bitshift : Int32

    # Creates a new map.
    #
    # The *initial_capacity* is the number of entries the map should hold across
    # all buckets. It will be clamped to at least as many buckets the map will
    # hold, then elevated to the next power of two in each bucket.
    #
    # The *buckets_count* is the number of buckets in the map. What matters is the
    # actual parallelism (number of hardware threads) of the CPU rather than the
    # total number of threads, but if your application only has 5 threads,
    # running on a CPU with 32 cores, you might want to limit the buckets' count
    # to the next power of two of 5 × 4 (32), instead of the default (128).
    def initialize(initial_capacity : Int32 = 8, buckets_count : Int32 = self.class.default_buckets_count)
      buckets_count = Math.pw2ceil(buckets_count.clamp(1..))
      capacity = (initial_capacity + (buckets_count - 1)) & ~(buckets_count - 1)

      @bitshift = (64 - buckets_count.trailing_zeros_count).to_i32

      @buckets = Slice(Bucket(K, V)).new(buckets_count) do
        Bucket(K, V).new(capacity // buckets_count)
      end
    end

    protected def initialize(@buckets, @bitshift, size : Int32)
    end

    def size : Int32
      size = 0
      each_bucket { |bucket| size += bucket.value.@h.size }
      size
    end

    def empty? : Bool
      each_bucket { |bucket| return false unless bucket.value.@h.empty? }
      true
    end

    def each(& : (K, V) ->) : Nil
      each_bucket do |bucket|
        next if bucket.value.@h.empty?

        bucket.value.read do
          bucket.value.@h.each { |key, value| yield key, value }
        end
      end
    end

    def each_key(& : K ->) : Nil
      each { |k, _| yield k }
    end

    def each_value(& : V ->) : Nil
      each { |_, v| yield v }
    end

    def keys : Array(K)
      keys = Array(K).new(size)
      each { |k, _| keys << k }
      keys
    end

    def values : Array(V)
      values = Array(V).new(size)
      each { |_, v| values << v }
      values
    end

    def has_key?(key : K) : Bool
      hash, bucket = determine_bucket(key)
      return false if bucket.value.@h.empty?

      bucket.value.read do
        return bucket.value.@h.has_key?(key, hash)
      end
    end

    def [](key : K) : V
      fetch(key) { raise KeyError.new "Missing key: #{key.inspect}" }
    end

    def []?(key : K) : V?
      fetch(key) { nil }
    end

    def fetch(key : K, default : U) : V | U forall U
      fetch(key) { default }
    end

    def fetch(key : K, & : -> U) : V | U forall U
      return yield if empty?

      hash, bucket = determine_bucket(key)
      return yield if bucket.value.@h.empty?

      bucket.value.read do
        bucket.value.@h.fetch(key, hash) { yield }
      end
    end

    def []=(key : K, value : V) : V
      put(key, value)
    end

    def put(key : K, value : V) : V
      hash, bucket = determine_bucket(key)

      bucket.value.write do
        bucket.value.@h.put(key, hash, value)
      end

      value
    end

    def put_if_absent(key : K, value : V) : V
      put_if_absent(key) { value }
    end

    def put_if_absent(key : K, & : K -> V) : V
      hash, bucket = determine_bucket(key)

      bucket.value.write do
        bucket.value.@h.fetch(key, hash) do
          value = yield key
          bucket.value.@h.put(key, hash, value)
          value
        end
      end
    end

    def update(key : K, & : V -> V) : V
      hash, bucket = determine_bucket(key)
      bucket.value.write do
        bucket.value.@h.update(key, hash) do |old_value|
          yield old_value
        end
      end
    end

    def delete(key : K) : V?
      delete(key) { nil }
    end

    def delete(key : K, & : -> U) : V | U forall U
      unless empty?
        hash, bucket = determine_bucket(key)

        unless bucket.value.@h.empty?
          value = nil
          removed = false

          bucket.value.write do
            value, removed = bucket.value.@h.delete(key, hash)
          end

          return value if removed
        end
      end

      yield
    end

    # TODO
    def clear : Nil
      raise NotImplementedError.new
    end

    # :nodoc:
    def clone : Map(K, V)
      raise NotImplementedError.new
    end

    def dup : Map(K, V)
      size = 0
      buckets = Slice(Bucket(K, V)).new(@buckets.size) do |i|
        bucket = @buckets.to_unsafe + i
        bucket.value.read do
          copy = Bucket(K, V).new(bucket.value.@h.capacity)
          size += copy.@h.size = bucket.value.@h.size
          copy.@h.@entries.copy_from(bucket.value.@h.@entries, bucket.value.@h.capacity)
          copy
        end
      end
      Map(K, V).new(buckets, @bitshift, size)
    end

    def to_h : Hash(K, V)
      hash = Hash(K, V).new(size)
      each_bucket do |bucket|
        bucket.value.read do
          bucket.value.@h.each do |k, v|
            hash[k] = v
          end
        end
      end
      hash
    end

    def to_a : Array({K, V})
      array = Array({K, V}).new(size)
      each_bucket do |bucket|
        bucket.value.read do
          bucket.value.@h.each do |k, v|
            array << {k, v}
          end
        end
      end
      array
    end

    # :nodoc:
    def hash(hasher)
      raise NotImplementedError.new
    end

    def rehash : Nil
      each_bucket do |bucket|
        bucket.value.write { bucket.value.@h.rehash }
      end
    end

    private def each_bucket(&)
      ptr = @buckets.to_unsafe
      @buckets.size.times { |i| yield ptr + i }
    end

    private def determine_bucket(key)
      hash = key.hash
      i = hash >> @bitshift
      raise "BUG: Sync::Map bucket index is out of bounds" unless 0 <= i < @buckets.size
      {hash, @buckets.to_unsafe + i}
    end
  end
end
