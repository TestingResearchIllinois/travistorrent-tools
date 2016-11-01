require 'bunny'

# Abstracts access to RabbitMQ via lazy loading

def rabbit_con
  @rabbit_con = Bunny.new
  @rabbit_con.start
  @rabbit_con
end

def rabbit_channel
  @channel = rabbit_con.create_channel if @channel.nil?
  @channel
end

def download_queue
  @download_queue = rabbit_channel.queue("download_build_queue", :durable => true) if @download_queue.nil?
  @download_queue
end

def close_rabbit
  rabbit_con.close
end