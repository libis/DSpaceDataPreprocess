#!/usr/bin/env ruby
# #################################################################################
#
# (c) 2012 LIBIS/KU Leuven
# http://www.libis.be, http://www.kuleuven.be
#
# mehmet (dot) celik (at) libis (dot)be
#
# Disclaimer
# THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESSED OR IMPLIED WARRANTIES, 
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
# FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE REGENTS OR 
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, 
# OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
# THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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