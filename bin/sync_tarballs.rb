# require "archive"
require 'nokogiri'
require 'open-uri'
require 'rubygems/package'
require 'zlib'

def syncTarball(localFolder)
  proj = File.basename(localFolder)
  puts "Project: "+proj
  @entries = {}
  remoteURL = "https://travistorrent.testroots.org/buildlogs/rubyjava/"
  Dir.glob(localFolder+"/*.tar.gz").each do |f|
    puts f
    File.open(f, "rb") do |file|
      Gem::Package::TarReader.new(Zlib::GzipReader.wrap(file)) do |tar|
        tar.each do |entry|
          if entry.file?
            @entries[File.basename(entry.full_name)] = 1
          end
        end
      end
    end
  end

  gz = nil
  newArchive = nil
  done = 0
  doc = Nokogiri::HTML(open(URI::join(remoteURL,proj)))
  hrefs = doc.css("a").map do |link|
    if (href = link.attr("href")) && !href.empty?
      next if File.extname(href) != ".log"
      next if @entries[href] == 1
      if newArchive == nil
        time1 = Time.new
        file = File.open((localFolder + '/' + time1.strftime("%Y-%m-%d-%H-%M")+'-'+proj+".tar.gz"), "wb")
        gz = Zlib::GzipWriter.wrap(file)
        newArchive = Gem::Package::TarWriter.new(gz)
      end
      puts URI::join(remoteURL,proj+"/"+href)
      stream = open(URI::join(remoteURL,proj+"/"+href))

      newArchive.add_file_simple((proj + '/' + href),0444, stream.length) do |io|
        io.write(stream.read)
      end
    end
  end.compact.uniq
  if gz
    gz.close
  end
end

if (ARGV[0].nil?)
  puts 'Missing argument(s)!'
  puts ''
  puts 'usage: sync_tarballs.rb directory'
  exit(1)
end

syncTarball(ARGV[0])

