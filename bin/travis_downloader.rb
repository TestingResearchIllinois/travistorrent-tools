#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'travis'
require 'json'

conn = Bunny.new
conn.start

ch   = conn.create_channel
q    = ch.queue("download_build_queue", :durable => true)

ch.prefetch(1)
puts " [*] Waiting for messages. To exit press CTRL+C"

begin
  q.subscribe(:manual_ack => true, :block => true) do |delivery_info, properties, body|
    puts " [x] Received '#{body}'"
    # imitate some work
    my_message = JSON.parse(body)
    project_name = my_message['project']
    build_number = my_message['build']

    # TODO (MMB) This is a clone with travis_poller. Write some nicer library function to handle this
    begin
      project = Travis::Repository.find(project_name)
    rescue NoMethodError => e
      # TODO (MMB) log something clever
      # high-speed exit point
      next;
    end

    if project.nil?
      # TODO (MMB) log something clever
      # high-speed exit point
      next;
    end

    build = project.build(build_number)

    # TODO (MMB) retrieve some basic API statistics from build
    build.jobs.each do |job|
      puts " [#{project_name}] Downloading #{build_number}/#{job.number}"
      # TODO (MMB) download build job
      # TODO (MMB) dispatch analysis of buildlogs
    end

    sleep 0.01
    puts " [x] Done"
    ch.ack(delivery_info.delivery_tag)
  end
rescue Interrupt => _
  conn.close
end