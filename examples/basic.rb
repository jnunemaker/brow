require_relative "../lib/brow"

client = Brow::Client.new({
  host: "requestbin.net",
  path: "/r/c5tqqybi",
  ssl: true,
})

50.times do |n|
  client.record({number: n})
end

client.flush
