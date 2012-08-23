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
require 'yaml'

class ConfigFile
  @config = {}      
 
  def self.[](key)
    init
    @config[key]
  end
  
  def self.[]=(key,value)    
    @config[key] = value
    File.open('config.yml', 'w') do |f|
      f.puts @config.to_yaml
    end
  end  
  
  private
  
  def self.init
    if @config.empty?
      config = YAML::load_file('config.yml') 
      @config = process(config)
    end
  end  
private 
  def self.process(config)
    config_hash = {}
    config.each do |k,v|
      if config[k].is_a?(Hash)
        v = process(v)
      end
      config.delete(k)      
      config_hash.store(k.to_sym, v)
    end

    config = config_hash
  end  
end
