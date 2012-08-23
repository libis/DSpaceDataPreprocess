require 'uri'

class PrimoRestBuilder
  
  INDEX_MAP = {'sys'                => 'sys',
               'any'                => 'any',
               'title'              => 'any',
               'author'             => 'facet_creator',               
               'subject'            => 'facet_topic',       
               'library'            => 'facet_library',
               'collection'         => 'collection',
               'callnumber'         => 'callnumber',
               'year'               => 'facet_creationdate',
               'isbn'               => 'any',
               'issn'               => 'any',
               'resource_type'      => 'rtype',
               'acq_date'           => 'adate',
               'acq_method'         => 'amethod',
               'acq_local'          => 'alocal',
               'acq_source'         => 'asource'
              }  
  
  def build(parsed_query = [], options = {})
    return "" if parsed_query.empty?
    options.each do |k,v|
      if k.is_a?(Symbol)
        options.store(k.to_s, v) 
        options.delete(k)
      end
    end
        
    host_           = options['host'] || '127.0.0.1:1701'
    from_           = options['from'] || 1
    step_           = options['step'] || 10
    institution_    = options['institution'] || 'PRIMO'
    on_campus_      = options.include?('institution') || false
    remote_search_  = false

    if options.include?('ip') && options.include?('location') && options.include?('more')
      ip_             = options['ip'] if options.include?('ip')
      location_       = options['location'] if options.include?('location')
      more_           = options.include?('more') ? options['more'] : '1'
      remote_search_  = true
    end

    url = ""

    base        = "http://#{host_}/PrimoWebServices/xservice/search/brief?"
    query       = serialize_query(parsed_query)
    institution = "institution=#{institution_}"
    on_campus   = "onCampus=#{on_campus_}"
    from_to     = "indx=#{from_}&bulkSize=#{step_}"
    misc        = "dym=true&highlight=true&lang=eng"

    if @remote_search
      ip = "ip=#{ip_}"
      loc = "loc=#{location_}"
      more = "more=#{more_}"
      query_timeout = 60
      url = "#{institution}&#{query}&#{on_campus}&#{ip}&#{from_to}&#{misc}&#{loc}&#{more}"
    else
      url = "#{institution}&#{query}&#{on_campus}&#{from_to}&#{misc}"
    end
    
    "#{base}#{URI::encode(url)}"    
  rescue Exception => e
    puts e.message    
    raise "Error building query"
  end
  
  def serialize_query(parsed_query)
    query_string = ""
    parsed_query.each do |q|
      query_value = ""
      if INDEX_MAP.include?(q[:index])
        if q.include?(:term)
          query_value = q[:term]
        else
          raise ArgumentError, 'Couldn\'t find a term to parse'
        end
      
        query_string += '&' if query_string.size > 0
        query_string += "query=#{INDEX_MAP[q[:index]]},#{q[:match]},#{query_value}"
      end
    end
    query_string
  end
  
end
