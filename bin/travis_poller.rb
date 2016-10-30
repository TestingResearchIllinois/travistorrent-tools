#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'fileutils'
require 'mongo'
require 'travis'

def read_projects
  projects_file = File.new('projects.txt', 'r')
  projects = projects_file.readlines.uniq.compact.map do |elem|
    elem.strip
  end
  projects.select! do |elem|
    elem != ''
  end

  exit(0) if projects.empty?
  projects
end

def setup_rabbit
  rabbit_con = Bunny.new
  rabbit_con.start
  channel = rabbit_con.create_channel
  @queue = channel.queue("download_build_queue", :durable => true)
  rabbit_con
end

def setup_mongo
  mongo_client = Mongo::Client.new(['127.0.0.1:27017'], :database => 'm_travistorrent')
  db = mongo_client.database
  Mongo::Logger.logger.level = ::Logger::FATAL

  @collection = mongo_client[:projects]
  @collection.indexes.create_one({name: 1}, unique: true)
end

def check_projects(projects)
  # TODO (MMB) This is an over simplification of the project meta model. We probably want to store failed
  # builds, downloaded builds, failed downloads etc.
  projects.each do |project|
    mongo_project = @collection.find({name: project}).first
    mongo_project ? local_highest_build = mongo_project[:latest_build] : local_highest_build = 0

    remote_project = Travis::Repository.find(project)
    if remote_project.nil?
      # TODO (MMB) log something clever
      # high-speed exit point
      next;
    end

    remote_highest_build = remote_project.last_build_number.to_i
    puts " [#{project}] Remote highest build: #{remote_highest_build}; local #{local_highest_build}"

    # high-speed exit point
    next if remote_highest_build == local_highest_build

    enqueue_build_downloads(local_highest_build, remote_highest_build, project)
  end
end

def enqueue_build_downloads(from, to, project)
  new_builds = (from..to).to_a
  new_builds.each do |build|
    msg = "#{project} #{build}"
    @queue.publish(msg, :persistent => true)
    puts " [x] Sent #{msg}"
  end

  @collection.update_one({"name": project},
                         {"name": project, "latest_build" => to},
                         {"upsert": true})
end

projects = read_projects

rabbit_con = setup_rabbit
setup_mongo

check_projects(projects)

rabbit_con.close
