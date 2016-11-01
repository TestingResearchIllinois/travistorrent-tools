require 'mongo'

def setup_mongo
  @mongo_client = Mongo::Client.new(['127.0.0.1:27017'], :database => 'm_travistorrent')
  Mongo::Logger.logger.level = ::Logger::FATAL
end

def setup_events_collection
  @mongo_events = @mongo_client[:projects]

  # Creating indices in MongoDB is idempotent. So it only creates the index only if it doesn't already exist.
  @mongo_events.indexes.create_one({name: 1}, unique: true)
end

def mongo_events
  setup_mongo if @mongo_client.nil?
  setup_events_collection if @mongo_events.nil?
  @mongo_events
end

def close_mongo
  @mongo_client.close
end