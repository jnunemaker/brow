require_relative "../lib/brow"
require_relative "echo_server"

Brow.logger = Logger.new(STDOUT)
Brow.logger.level = Logger::INFO

client = Brow::Client.new({
  url: "http://localhost:#{EchoServer.instance.port}",
  batch_size: 500,
})

running = true
n = 0

trap("INT") {
  puts "Shutting down"
  running = false
}

while running
  n += 1
  rand(5_000).times { client.push(n: n) }

  puts "Queue size: #{client.worker.queue.size}"
  # Pretend to work
  sleep(rand)
end
