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

if ARGV.size != 1
  puts "Converts a single record. Saves output in Staging directory(see config.yml)"
  puts "USAGE: #{$0} xmlfile"
  exit 1
end

i = 0
f =  ARGV[0]
l = DSpace.new
x = Nokogiri::XML(open(f))

didl_xml_file = x.css('metadata')
identifier    = x.css('identifier').text

begin
  mods = l.patch_record(didl_xml_file)
  File.open("#{ConfigFile[:staging_dir]}/mods.xml", "w") do |fo|
    fo.puts mods
  end
  
  l.save(mods, "#{identifier}", Time.now.xmlschema, i)
  puts "saving #{f}"
  
rescue Exception => e
  puts "error in file #{f}"  
  puts e.message
  puts e.backtrace
end
