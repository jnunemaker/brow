require_relative "../lib/brow"

client = Brow::Client.new

50.times do |n|
  client.record({number: n})
end

client.flush
