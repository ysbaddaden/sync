attempts = 3
types = %w[hash map]
profiles = %w[reader exchange rapid_grow]
concurrencies = %w[1 2 4 8 16 24 32 64]

table = Hash(String, Hash(String, Hash(String, Array(Float64)))).new
io = IO::Memory.new

types.each do |type|
  table[type] = {} of String => Hash(String, Array(Float64))

  profiles.each do |mode|
    table[type][mode] = {} of String => Array(Float64)

    concurrencies.each do |concurrency|
      STDERR.print "#{type} :: #{mode} :: #{concurrency}   \r"

      table[type][mode][concurrency] = attempts.times.map do
        io.rewind
        Process.run("./bench/map", {type, mode}, env: {"C" => concurrency}, output: io)
        _, _, _, mops, _ = io.rewind.to_s.split('\r').last.strip.split(' ')
        mops.to_f
      end.to_a
    end
  end
end

concurrencies.each do |concurrency|
  STDOUT.print concurrency
  profiles.each do |mode|
    types.each do |type|
      STDOUT.print '\t'
      STDOUT.print table[type][mode][concurrency].sum / attempts / 1_000_000
    end
  end
  puts
end
