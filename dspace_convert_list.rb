#!/usr/bin/env ruby
# #################################################################################
#
# (c) 2012 LIBIS/KU Leuven
# http://www.libis.be, http://www.kuleuven.be
#
# mehmet (dot) celik (at) libis (dot)be
#
# The complete project is licensed under GPLv3
# (http://www.gnu.org/licenses/gpl-3.0.html)
#
$LOAD_PATH << './lib'
require 'rubygems'
require 'bundler'
Bundler.setup

require 'dspace'
require 'oai'
require 'config_file'


if ARGV.size != 1
  puts "Pulls a list of records from an OAI service(config.yml dspace => host)"
  puts "USAGE: #{$0} list_with_record_ids"
  exit 1
end

i = 0
file_name =  ARGV[0]
l = DSpace.new

File.open(file_name, 'r') do |f| 
  recordid = ''
  while !f.eof do
    recordid = f.readline.chomp
    client = OAI::Client.new(ConfigFile[:dspace][:host], :parser => 'nokogiri')

    begin
      result = client.get_record(:identifier => "#{ConfigFile[:dspace][:urn]}#{recordid}", :metadata_prefix => 'mods')
      
      unless result.nil?
        x = result.record.metadata
        identifier    = result.record.header.identifier

        begin          
          mods = l.patch_record(x)

          l.save(mods, "#{identifier}", Time.now.xmlschema, i)
          puts "saving #{identifier}"
          i += 1
        rescue Exception => e
          puts "error in file #{f}"  
          puts e.message
          puts e.backtrace
        end    
      end
    rescue Exception => e
      puts "#{recordid} -- #{e.message}"
      File.open("#{ConfigFile[:log_dir]}/bad_dspace.log", 'a') do |bf|
        bf.puts recordid
      end
    end
  end
end