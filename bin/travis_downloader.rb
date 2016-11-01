#!/usr/bin/env ruby
# encoding: utf-8

require 'travis'
require 'json'

load '../lib/rabbitmq_access.rb'


@buildlog_path = './logs/'

def buildlog_dir(repo)
  parent_dir = File.join(@buildlog_path, repo.gsub(/\//, '@'))
  FileUtils::mkdir_p(parent_dir)
end

def download_and_store_job(job, build_id, build_commit_sha, project_name)
  logfile = File.join(buildlog_dir(project_name), "#{build_id}_#{build_commit_sha}_#{job.id.to_s}.log")
  # do not re-download already downloaded buildlogs
  return if File.exists?(logfile)

  begin
    log = job.log.body
  rescue
    log_url = "http://s3.amazonaws.com/archive.travis-ci.org/jobs/#{job.id}/log.txt"
    log = Net::HTTP.get_response(URI.parse(log_url)).body
  end

  # TODO (MMB) check if logfile is non-empty; only accept if non-empty
  File.open(logfile, 'w') { |f| f.puts log }
  log = '' # necessary to enable GC of previously stored value, otherwise: memory leak
end


rabbit_channel.prefetch(1)
puts " [*] Waiting for messages. To exit press CTRL+C"

begin
  download_queue.subscribe(:manual_ack => true, :block => true) do |delivery_info, properties, body|
    puts " [x] Received '#{body}'"
    my_message = JSON.parse(body, :symbolize_names => true)
    project_name = my_message[:project]
    build_number = my_message[:build]

    # TODO (MMB) This is a clone with travis_poller. Write some nicer library function to handle this
    begin
      project = Travis::Repository.find(project_name)
    rescue NoMethodError => e
      # TODO (MMB) log something clever
      # high-speed exit point
      next
    end

    if project.nil?
      # TODO (MMB) log something clever
      # high-speed exit point
      next
    end

    # Prefetch build attributes to reduce number of calls to Travis API
    build = project.build(build_number)
    build_id = build.id
    build_commit_sha = build.commit.sha

    # TODO (MMB) retrieve some basic API statistics from build
    build.jobs.each do |job|
      puts " [#{project_name}] Downloading #{build_number}/#{job.number}"
      download_and_store_job(job, build_id, build_commit_sha, project_name)
      # TODO (MMB) dispatch analysis of buildlogs
    end

    puts " [x] Done"
    rabbit_channel.ack(delivery_info.delivery_tag)
  end
rescue Interrupt => _
  rabbit_con.close
end