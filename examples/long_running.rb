require_relative "../lib/brow"
# require_relative "echo_server"

Brow.logger = Logger.new(STDOUT)
Brow.logger.level = Logger::INFO

port = ENV.fetch("PORT") { EchoServer.instance.port }

client = Brow::Client.new({
  url: "http://localhost:#{port}",
  batch_size: 1_000,
})

running = true

trap("INT") {
  puts "Shutting down"
  running = false
}

while running
  rand(10_000).times { client.push("foo" => "bar") }

  puts "Queue size: #{client.worker.queue.size}"

  # Pretend to work
  sleep(rand)
end
