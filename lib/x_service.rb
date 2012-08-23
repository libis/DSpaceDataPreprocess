require 'nokogiri'
require 'open-uri'
require 'timeout'

class XService
  attr_accessor :error_handler, :result, :retry_query
  
  def initialize
    @error_handler = nil
  end
  
  def query(url, options = {})        
      options.each do |k,v|
        options.delete(k)
        options.store(k.to_s, v)
      end    
      
      @retry_query = true
      @result = nil
      while @retry_query
        @retry_query = false
        query_timeout = options['query_timeout'] || 3
        Timeout::timeout(query_timeout) do
          @result = Nokogiri::XML(open(url))
        end
        #errors are returned differently depending on the calling service 
        #so provide your own sanity check     
        @error_handler.call(self) unless @error_handler.nil?        
      end
            
      @result
    rescue Timeout::Error
      raise "Query timedout."
      return nil
    rescue Exception => e
      #TODO: Check if there is a need to handle HTTP errors 404, 500, ...
      raise "Error during XService call :\nmessage=#{e.message}"
      return nil    
  end
end