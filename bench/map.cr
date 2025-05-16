# Port of libcuckoo's universal benchmark.
#
# Copyright (C) 2013, Carnegie Mellon University and Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# See https://github.com/efficient/libcuckoo/blob/master/tests/universal-benchmark

require "wait_group"
require "../src/map"
require "../src/rw_lock"

class Workload(T, K, V)
  enum OP
    READ
    INSERT
    ERASE
    UPDATE
    UPSERT
  end

  def initialize(read_percentage = 0,
                 insert_percentage = 0,
                 update_percentage = 0,
                 upsert_percentage = 0,
                 erase_percentage = 0,
                 initial_capacity = 1 << 25,
                 prefill_percentage = 0,
                 total_ops_percentage = 75,
                 concurrency = 8)
    {read_percentage, insert_percentage, erase_percentage, update_percentage, upsert_percentage, prefill_percentage, total_ops_percentage}.each do |value|
      abort "Percentage must be between 0 and 100" unless 0 <= value <= 100
    end
    unless read_percentage + insert_percentage + erase_percentage + update_percentage + upsert_percentage == 100
      abort "Operation mix must sum to 100 in total"
    end

    @tbl = T.new(initial_capacity)

    @ops = Array(OP).new(100)
    read_percentage.times { @ops << OP::READ }
    insert_percentage.times { @ops << OP::INSERT }
    erase_percentage.times { @ops << OP::ERASE }
    update_percentage.times { @ops << OP::UPDATE }
    upsert_percentage.times { @ops << OP::UPSERT }
    @ops.shuffle!

    total_ops = initial_capacity.to_u64 * total_ops_percentage // 100
    prefill = initial_capacity.to_u64 * prefill_percentage // 100

    max_insert_ops = (total_ops + 99) // 100 * (insert_percentage + upsert_percentage)
    insert_keys = {initial_capacity, max_insert_ops}.max + prefill
    insert_keys_per_fiber = Math.pw2ceil(insert_keys // concurrency)
    prefill_per_fiber = prefill // concurrency

    STDERR.print "gen nums...\r"
    nums = Array(Array(UInt64)).new(concurrency) do
      # note: could be parallelized with a split prng
      Array(UInt64).new(insert_keys_per_fiber) { Random.rand(UInt64) }
    end

    STDERR.print "gen keys...\r"
    keys = Array(Array(K)).new(concurrency) { Array(K).new(insert_keys_per_fiber) }

    WaitGroup.wait do |wg|
      concurrency.times { |c| gen_keys(wg, insert_keys_per_fiber, keys[c], nums[c]) }
    end

    if prefill > 0
      STDERR.print "prefill...\r"
      WaitGroup.wait do |wg|
        concurrency.times { |c| prefill(wg, prefill_per_fiber, keys[c], nums[c]) }
      end
    end

    STDERR.print "running...\r"
    num_ops_per_fiber = total_ops // concurrency

    elapsed = Time.measure do
      WaitGroup.wait do |wg|
        concurrency.times { |c| mix(wg, num_ops_per_fiber, keys[c], nums[c], prefill_per_fiber) }
      end
    end

    seconds_elapsed = elapsed.total_seconds
    ops_per_second = total_ops / seconds_elapsed

    STDOUT.print "#{concurrency} #{elapsed.total_milliseconds.to_i} ms #{ops_per_second} op/s\n"
  end

  def gen_keys(wg, size, keys, nums)
    wg.spawn do
      size.times do |i|
        num = nums[i]
        {% if K == String %}
          keys << String.new(pointerof(num).as(UInt8*), sizeof(typeof(num)))
        {% elsif K < Int %}
          keys << K.new!(num)
        {% else %}
          {% raise "Unsupported K: #{K}" %}
        {% end %}
      end
    end
  end

  def prefill(wg, size, keys, nums)
    wg.spawn do
      size.times { |i| @tbl.insert(keys[i], nums[i]) }
    end
  end

  def mix(wg, num_ops, keys, nums, prefill)
    abort "failed assertion: keys.size > 4" unless keys.size > 4

    wg.spawn do
      erase_seq = 0
      insert_seq = prefill
      find_seq = 0

      a = keys.size // 2 + 1
      c = keys.size // 4 + 1
      find_seq_mask = keys.size - 1
      find_seq_update = -> { find_seq = (a &* find_seq &+ c) & find_seq_mask }

      v = uninitialized V

      key = ->(n : Int32 | UInt64) { keys[n]? || raise "BUG: no key at index=#{n} size=#{keys.size}" }

      i = 0
      while i < num_ops
        @ops.each do |op|
          break if i >= num_ops

          case op
          when OP::READ
            if erase_seq <= find_seq < insert_seq
              v = @tbl.read(key.call(find_seq))
            end
            find_seq_update.call
          when OP::INSERT
            @tbl.insert(key.call(insert_seq), nums[insert_seq])
            insert_seq &+= 1
          when OP::ERASE
            if erase_seq == insert_seq
              @tbl.erase(key.call(find_seq))
              find_seq_update.call
            else
              @tbl.erase(key.call(erase_seq))
              erase_seq &+= 1
            end
          when OP::UPDATE
            if erase_seq <= find_seq < insert_seq
              @tbl.update(key.call(find_seq), nums[find_seq])
            end
            find_seq_update.call
          when OP::UPSERT
            n = {find_seq, insert_seq}.min
            find_seq_update
            @tbl.upsert(key.call(n)) { |v| v }
            insert_seq &+= 1 if n == insert_seq
          end

          i += 1
        end
      end
    end
  end
end

abstract struct Tbl(K, V)
  abstract def read(key : K) : V
  abstract def insert(key : K, value : V) : Nil
  abstract def update(key : K, value : V) : Nil
  abstract def upsert(key : K, & : V -> V) : Nil
  abstract def erase(key : K) : V?
end

struct HashTbl(K, V) < Tbl(K, V)
  def initialize(initial_capacity)
    @hash = Hash(K, V).new(initial_capacity: initial_capacity)
    @lock = Sync::RWLock.new
  end

  def read(key : K) : V
    @lock.read { @hash[key] }
  end

  def insert(key : K, value : V) : Nil
    @lock.write { @hash[key] = value }
  end

  def update(key : K, value : V) : Nil
    @lock.write { @hash[key] = value }
  end

  def upsert(key : K, & : V -> V) : Nil
    @lock.write { @hash.update(key) { |v| yield v } }
  end

  def erase(key : K) : V?
    @lock.write { @hash.delete(key) }
  end
end

struct MapTbl(K, V) < Tbl(K, V)
  def initialize(initial_capacity)
    @map = Sync::Map(K, V).new(initial_capacity)
  end

  def read(key : K) : V
    @map[key]
  end

  def insert(key : K, value : V) : Nil
    @map[key] = value
  end

  def update(key : K, value : V) : Nil
    @map[key] = value
  end

  def upsert(key : K, & : V -> V) : Nil
    @map.update(key) { |v| yield v }
  end

  def erase(key : K) : V?
    @map.delete(key)
  end
end

mt = Fiber::ExecutionContext::MultiThreaded.new("MT", Fiber::ExecutionContext.default_workers_count)
main = WaitGroup.new(1)

PROFILES = {
  "reader" => {
    "READ" => 98,
    "INSERT" => 1,
    "UPDATE" => 0,
    "UPSERT" => 0,
    "ERASE" => 1,
  },
  "exchange" => {
    "READ" => 10,
    "INSERT" => 40,
    "UPDATE" => 10,
    "UPSERT" => 0,
    "ERASE" => 40,
  },
  "rapid_grow" => {
    "READ" => 5,
    "INSERT" => 80,
    "UPDATE" => 10,
    "UPSERT" => 0,
    "ERASE" => 5,
  }
}

read_percentage = 0
insert_percentage = 0
update_percentage = 0
upsert_percentage = 0
erase_percentage = 0
mode = ""

ARGV.each do |arg|
  if profile = PROFILES[arg.downcase]?
    read_percentage = profile["READ"]
    insert_percentage = profile["INSERT"]
    update_percentage = profile["UPDATE"]
    upsert_percentage = profile["UPSERT"]
    erase_percentage = profile["ERASE"]
    mode = arg.downcase
    break
  end
end

if v = ENV["READ"]?.try(&.to_i?)
  read_percentage = v
end
if v = ENV["INSERT"]?.try(&.to_i?)
  insert_percentage = v
end
if v = ENV["UPDATE"]?.try(&.to_i?)
  update_percentage = v
end
if v = ENV["UPSERT"]?.try(&.to_i?)
  upsert_percentage = v
end
if v = ENV["ERASE"]?.try(&.to_i?)
  erase_percentage = v
end

initial_capacity = ENV.fetch("N", "33554432").to_i
prefill_percentage = ENV.fetch("PREFILL", "0").to_i
total_ops_percentage = ENV.fetch("OPS", "75").to_i
concurrency = ENV.fetch("C", "8").to_i

mt.spawn do
  if ARGV.any? { |arg| arg == "hash" }
    Workload(HashTbl(String, UInt64), String, UInt64).new(
      read_percentage,
      insert_percentage,
      update_percentage,
      upsert_percentage,
      erase_percentage,
      initial_capacity,
      prefill_percentage,
      total_ops_percentage,
      concurrency)
  else
    Workload(MapTbl(String, UInt64), String, UInt64).new(
      read_percentage,
      insert_percentage,
      update_percentage,
      upsert_percentage,
      erase_percentage,
      initial_capacity,
      prefill_percentage,
      total_ops_percentage,
      concurrency)
  end
ensure
  main.done
end

main.wait
