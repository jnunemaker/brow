require_relative "../lib/brow"
require_relative "echo_server"

client = Brow::Client.new({
  url: "http://localhost:#{EchoServer.instance.port}",
  batch_size: 10,
})

client.push({
  now: Time.now.utc,
  parent: true,
})

pid = fork {
  client.push({
    now: Time.now.utc,
    child: true,
  })
}
Process.waitpid pid, 0
