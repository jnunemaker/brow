require_relative "../lib/brow"

client = Brow::Client.new({
  url: "https://requestbin.net/r/2bp3p3vn",
  batch_size: 10,
})

5.times do |n|
  client.push(n: n, parent: true)
end

pid = fork {
  15.times do |n|
    client.push({
      number: n,
      now: Time.now.utc,
    })
  end
}
Process.waitpid pid, 0
