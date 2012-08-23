module QueryBuilder
  
  class Factory
    attr_reader :builder, :parser
    
    def initialize(parser = :lucene, builder = :primo_html)
      @parser  = self.class.const_get("#{camelize_it(parser)}Parser")
      @builder = self.class.const_get("#{camelize_it(builder)}Builder")      
    rescue Exception => e
      puts e.message
      exit 1
    end
    
    def build(query = "", options = {})        
      parser = @parser.new
      builder = @builder.new

      parsed_query = parser.parse(query)

      url = builder.build(parsed_query, options)
    end    
    
    private
    def camelize_it(s)
      s.to_s.split('_').map {|m| m.capitalize}.join
    end    
    
  end
end