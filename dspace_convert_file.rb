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
