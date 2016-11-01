require 'mongo'

# Abstracts access to MongoDB via lazy loading

def mongo_client
  if @mongo_client.nil?
    @mongo_client = Mongo::Client.new(['127.0.0.1:27017'], :database => 'm_travistorrent')
    Mongo::Logger.logger.level = ::Logger::FATAL
  end
  @mongo_client
end

def mongo_events
  if @mongo_events.nil?
    @mongo_events = mongo_client[:events]

    # Creating indices in MongoDB is idempotent. So it only creates the index only if it doesn't already exist.
    @mongo_events.indexes.create_one({name: 1}, unique: true)
  end
  @mongo_events
end

def close_mongo
  mongo_client.close
end