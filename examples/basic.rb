require_relative "../lib/brow"

client = Brow::Client.new(max_queue_size: 10_000)

50.times do |n|
  client.record({number: n})
end

client.flush
