#!/usr/bin/env ruby
# encoding: utf-8

require 'fileutils'
require 'travis'

load '../lib/mongodb_access.rb'
load '../lib/rabbitmq_access.rb'


# Reads in a list of projects and parses them for validity. Only returns projects with the format
# [alphanumeric]/[alphanumeric] and converts the GitHub format [alphanumeric]@[alphanumeric] to it if necessary
def read_projects
  projects_file = File.new('projects.txt', 'r')
  projects = projects_file.readlines.uniq.compact.map do |elem|
    elem.strip.gsub('@','/')
  end
  projects.select! do |elem|
    elem != '' and !/^[\w-]{1,100}\/[\w-]{1,100}$/.match(elem).nil?
  end

  exit(0) if projects.empty?
  projects
end

def check_projects(projects)
  # TODO (MMB) This is an over simplification of the project meta model. We probably want to store failed
  # builds, downloaded builds, failed downloads etc.
  projects.each do |project|
    # TODO (MMB) add getter for mongo_events and handle failures in there
    # TODO (MMB) query by id, and pull through the rest of the script
    mongo_project = mongo_events.find({name: project}).first
    mongo_project ? local_highest_build = mongo_project[:latest_build] : local_highest_build = 1

    begin
      remote_project = Travis::Repository.find(project)
    rescue NoMethodError => e
      # TODO (MMB) log something clever
      # high-speed exit point
      next
    end

    if remote_project.nil?
      # TODO (MMB) log something clever
      # project deleted?
      # high-speed exit point
      next
    end

    remote_highest_build = remote_project.last_build_number.to_i
    puts " [#{project}] Remote highest build: #{remote_highest_build}; local #{local_highest_build}"

    # high-speed exit point
    next if remote_highest_build <= local_highest_build
    # TODO (MMB) log something clever, as this is a very unexpected scenario

    enqueue_build_downloads(local_highest_build, remote_highest_build, project)
  end
end

def enqueue_build_downloads(from, to, project)
  new_builds = (from..to)
  new_builds.each do |build|
    my_hash = {:project => project, :build => build}
    msg = JSON.generate(my_hash)
    download_queue.publish(msg, :persistent => true)
    puts " [x] Sent #{msg}"
  end

  # TODO (MMB) Convert to event stream and push into travis_downloader
  mongo_events.update_one({"name": project},
                         {"name": project, "latest_build" => to},
                         {"upsert": true})
end

projects = read_projects
check_projects(projects)

close_mongo
close_rabbit