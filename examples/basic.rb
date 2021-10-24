require_relative "../lib/brow"

client = Brow::Client.new({
  url: "https://requestbin.net/r/4f09194m",
})

150.times do |n|
  client.push({
    number: n,
    now: Time.now.utc,
  })
end
