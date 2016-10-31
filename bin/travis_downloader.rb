#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'travis'
require 'json'

def download_and_store_job(job)
  begin
    log = job.log.body
  rescue
    log_url = "http://s3.amazonaws.com/archive.travis-ci.org/jobs/#{job.id}/log.txt"
    log = Net::HTTP.get_response(URI.parse(log_url)).body
  end
  File.open("logs/#{job.id}.log", 'w') { |f| f.puts log }
  log = '' # necessary to enable GC of previously stored value, otherwise: memory leak
end

# TODO (MMB) Factor out clone from travis poller
conn = Bunny.new
conn.start

ch = conn.create_channel
q = ch.queue("download_build_queue", :durable => true)

ch.prefetch(1)
puts " [*] Waiting for messages. To exit press CTRL+C"

begin
  q.subscribe(:manual_ack => true, :block => true) do |delivery_info, properties, body|
    puts " [x] Received '#{body}'"
    my_message = JSON.parse(body)
    project_name = my_message['project']
    build_number = my_message['build']

    # TODO (MMB) This is a clone with travis_poller. Write some nicer library function to handle this
    begin
      project = Travis::Repository.find(project_name)
    rescue NoMethodError => e
      # TODO (MMB) log something clever
      # high-speed exit point
      exit(1)
    end

    if project.nil?
      # TODO (MMB) log something clever
      # high-speed exit point
      exit(1)
    end

    build = project.build(build_number)

    # TODO (MMB) retrieve some basic API statistics from build
    build.jobs.each do |job|
      puts " [#{project_name}] Downloading #{build_number}/#{job.number}"
      download_and_store_job job
      # TODO (MMB) dispatch analysis of buildlogs
    end

    puts " [x] Done"
    ch.ack(delivery_info.delivery_tag)
  end
rescue Interrupt => _
  conn.close
end