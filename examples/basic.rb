require_relative "../lib/brow"

client = Brow::Client.new({
  url: "https://requestbin.net/r/rna67for",
})

50.times do |n|
  client.push({
    number: n,
    now: Time.now.utc,
  })
end

client.flush
