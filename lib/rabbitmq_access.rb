require 'bunny'

def setup_rabbit
  @rabbit_con = Bunny.new
  @rabbit_con.start
end

def setup_download_queue
  channel = @rabbit_con.create_channel
  @download_queue = channel.queue("download_build_queue", :durable => true)
end

def download_queue
  setup_rabbit if @rabbit_con.nil?
  setup_download_queue if @download_queue.nil?
  @download_queue
end

def close_rabbit
  @rabbit_con.close
end