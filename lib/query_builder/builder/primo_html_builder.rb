require 'uri'

class PrimoHtmlBuilder
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
                 'resource_type'      => 'facet_rtype',
                 'acq_date'           => 'adate',
                 'acq_method'         => 'amethod',
                 'acq_local'          => 'alocal',
                 'acq_source'         => 'asource'
                }    

    SCOPES = {'all' => 'scope:(LIRIAS),scope:(RESKUL),scope:("LIBIS"),scope:(KUL),scope:(ASSOC),scope:("LBS01"),scope:(ML),scope:(DTL),scope:(SFX),primo_central_multiple_fe',
              'local' => 'scope:(LIRIAS),scope:("LIBIS"),scope:(KUL),scope:(ASSOC),scope:("LBS01"),scope:(ML),scope:(DTL),scope:(SFX)'}


    def initialize
      #http://limo.libis.be/primo_library/libweb/action/dlDisplay.do?vid=KULeuven&docId=LBS01001383862&fromSitemap=0&afterPDS=true
      @host       = 'limo.libis.be'        
      @base_scope = 'all'
    end


    def build(parsed_query = [], options = {})
      return "" if parsed_query.empty?
      options.each do |k,v|
        if k.is_a?(Symbol)
          options.store(k.to_s, v) 
          options.delete(k)
        end
      end

      if (parsed_query.select {|q| INDEX_MAP[q[:index]] =~ /^facet/}).size > 0
        options['ct'] = 'facet'
      end    

      query = ""
      terms = []    
      host      = options['host'] || @host          
      base_path = options['base_path'] || '/primo_library/libweb/action/search.do'
      base_query = base_query_builder(options)    

      sys_index = !(parsed_query.select {|q| INDEX_MAP[q[:index]] =~ /^sys$/}).empty?
      if sys_index
        base_path = '/primo_library/libweb/action/dlDisplay.do'    
        base_query = base_query_builder_sys(options)
      end

  #    libraries = parsed_query.select {|s| s[:term] if INDEX_MAP[s[:index]].eql?('facet_library')}
  #    library = libraries.empty? ? "*" : libraries.first[:term].upcase 
      parsed_query.each do |q|
        if INDEX_MAP.include?(q[:index])

          if INDEX_MAP[q[:index]] =~ /^facet/
            query += "&fctN=#{INDEX_MAP[q[:index]]}&fctV=#{q[:term]}"
          elsif INDEX_MAP.include?(q[:index])
            case INDEX_MAP[q[:index]]
            when "any"
              terms << "#{q[:term]}"
            when "sys"
              terms << "#{q[:term]}"
            when "collection"
              terms << "Collection#{q[:term]}".gsub(/[\!\@\#\$\%\^\&\(\)\_\+\-\=\{\}\[\]\:\"\;\<\>\,\.\/\~\` ]/, '')
            when "callnumber"
              terms << "Callnumber#{q[:term]}".gsub(/[\!\@\#\$\%\^\&\(\)\_\+\-\=\{\}\[\]\:\"\;\<\>\,\.\/\~\` ]/, '')
            when "adate"
              terms << "AcquisitionDate#{q[:term]}".gsub(/[\!\@\#\$\%\^\&\(\)\_\+\-\=\{\}\[\]\:\"\;\<\>\,\.\/\~\` ]/, '')
            when "amethod"
              terms << "AcquisitionMethod#{q[:term]}".gsub(/[\!\@\#\$\%\^\&\(\)\_\+\-\=\{\}\[\]\:\"\;\<\>\,\.\/\~\` ]/, '')
            when "alocal"
              terms << "AcquisitionLocal#{q[:term]}".gsub(/[\!\@\#\$\%\^\&\(\)\_\+\-\=\{\}\[\]\:\"\;\<\>\,\.\/\~\` ]/, '')
            when "asource"
              terms << "AcquisitionSource#{q[:term]}".gsub(/[\!\@\#\$\%\^\&\(\)\_\+\-\=\{\}\[\]\:\"\;\<\>\,\.\/\~\` ]/, '')
            end
          end
        else
          terms << "#{q[:term]}"
        end
      end
      terms_string = terms.join(' AND ')

      base_query.each do |k,v|
        query += "&#{k}=#{v}"
      end

      if sys_index
        query = "docId=#{terms_string}#{query}"
      else
        query = "vl(freeText0)=#{terms_string}#{query}"
      end

      "http://#{host}#{base_path}?#{URI::encode(query)}"    

    end

    private
    def base_query_builder(options)
      scope     = SCOPES[options['scope']] || SCOPES[@base_scope]
      vid       = options['view'] || 'KULeuven'
      ct        = options['ct'] || 'search'    

      base_query = { 'dum'      => 'true',
                     'dscnt'    => 0,
                     'frbg'     => '',
                     'tab'      => 'local',
                     'srt'      => 'rank',
                     'mode'     => 'Basic',  
                     'indx'     => 1,
                     'fn'       => 'search',
                     'ct'       => ct,
                     'vid'      => vid,
                     'dstmp'    => Time.now.to_i,
                     'scp.scps' => scope  
                   }

    end

    def base_query_builder_sys(options)
      vid       = options['view'] || 'KULeuven'

      base_query = { 'fromSitemap' => 0,
                     'afterPDS'    => 'true',
                     'vid'         => vid      
                   }
    end  
  
end
