require_relative "../lib/brow"

client = Brow::Client.new({
  url: "https://requestbin.net/r/c5tqqybi",
})

50.times do |n|
  client.record({number: n})
end

client.flush
