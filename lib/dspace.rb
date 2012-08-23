require 'nokogiri'
require 'oai'
require 'logger'
require 'dspace/mods'
require 'zlib'
require 'time'
require 'archive/tar/minitar'
require 'config_file'

class DSpace
  attr_reader :from, :until, :logger
  
  def initialize
    @logger = Logger.new("#{ConfigFile[:log_dir]}/extract.log")

    Dir.chdir(ConfigFile[:staging_dir]) do |d|
      @logger.info('Cleaning records directory')
      Dir.glob('*.xml') do |t|
        File.delete(t) 
      end
    end    
  end
  
  def export(host, start_from = Time.at(0), step = 10000)
    @from  = start_from
    @until = Time.now
    
    
    @logger.info( "Exporting from: #{@from.xmlschema} until: #{@until.xmlschema}" )
    
    client = OAI::Client.new(host, :parser => 'nokogiri')

    result = client.list_records(:metadata_prefix => "mods", :from => @from, :until => @until)
    i=0
    prev_i = i
    run_once=true
    run_last=true
    empty_result = 0
    while empty_result < 5 && result && (run_last || run_once || (result.resumption_token && result.resumption_token.size != 0)) do
      run_once=false
      start_debugger = true
      result.each do |record|
        get_from    = record.header.datestamp
        identifier  = record.header.identifier
        status      = record.header.status

        c = ConfigFile[:dspace] 
        c[:start_from] = Time.parse(get_from).strftime('%d-%m-%Y %H:%M:%S')
        ConfigFile[:dspace] = c


        case record.header.status
        when 'deleted'
        oai_pmh_no_metadata = <<OAI_NM
<?xml version = "1.0" encoding = "UTF-8"?>
<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
  <responseDate>#DATESTAMP#</responseDate>
  <request>didl</request>
  <ListRecords>
    <record>
      <header status='deleted'>
        <identifier>#IDENTIFIER#</identifier>
        <datestamp>#DATESTAMP#</datestamp>
      </header>
    </record>
  </ListRecords>
</OAI-PMH>
OAI_NM
          oai_pmh_no_metadata.gsub!('#IDENTIFIER#', identifier)
          oai_pmh_no_metadata.gsub!('#DATESTAMP#', get_from)  

          File.open("#{ConfigFile[:staging_dir]}/dspace_#{i}.xml", 'w') do |f|
            f.puts oai_pmh_no_metadata
          end 
        else
          mods = ''
          links = []

          unless record.metadata.nil?
            mods = patch_record(record.metadata)
            save(mods, identifier, Time.now.xmlschema, i)
            start_debugger = false
          end
        end    
        
        if i.modulo(10000) == 0 && i != 0
          out_filename = pack_and_sack(prev_i, i)
          prev_i = i
          if block_given?
            yield out_filename
          end          
        end
        
        i += 1
      end
      empty_result += 1 if result.empty?

      @logger.info("Retrieving more data: #{result.resumption_token}")
      result = result.resumption_token.nil? || result.resumption_token.size == 0  ? nil : client.list_records(:resumption_token => result.resumption_token)
    end
    
    out_filename = pack_and_sack(prev_i, i)
    if block_given?
      yield out_filename
    end    
    
    return i
  end
  
  def pack_and_sack(prev_i, i)
    @logger.info("Harvested from #{prev_i}-#{i}")
    out_filename = "records__#{prev_i}_#{i}.tar.gz"          
    
    Dir.chdir(ConfigFile[:staging_dir]) do |d|
      begin                            
        zip = Zlib::GzipWriter.new(File.open(out_filename, 'wb'))
        tar = Archive::Tar::Minitar::Output.new(zip)

        Dir.glob('*.xml') do |entry|
          Archive::Tar::Minitar.pack_file(entry, tar)
          File.delete(entry) 
        end         
        
      rescue Exception => e
        @logger.info("#{e.message}")
        @logger.info('Error harvesting')
        exit 2
      ensure
        tar.close
      end
    end 
    
    sleep 5 
    return out_filename      
  end
  
  def patch_record(record)    
    mods = Nokogiri::XML::Document.parse('<empty />')
    links = []
        
    items = record.xpath('./didl:DIDL/didl:Item/didl:Item', 'didl' => 'urn:mpeg:mpeg21:2002:02-DIDL-NS')
    items.each do |item|
      link_context = ''
      type = item.xpath('.//rdf:type', 'rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#')[0].text()        
      case type
      when 'info:eu-repo/semantics/descriptiveMetadata'
        mods = item.xpath('.//mods:mods',{"mods" => "http://www.loc.gov/mods/v3"})[0]
        mods.add_namespace('xsi', "http://www.w3.org/2001/XMLSchema-instance")
        if mods.xpath('.//dai:daiList','dai' => 'info:eu-repo/dai').length > 0 && mods.xpath('.//dai:daiList','dai' => 'info:eu-repo/dai').first.has_attribute?('schemaLocation')
          mods.xpath('.//dai:daiList','dai' => 'info:eu-repo/dai').attribute('schemaLocation').value = 'info:eu-repo/dai http://purl.org/REP/standards/dai-extension.xsd'          
        end
      when 'info:eu-repo/semantics/humanStartPage' #object in context
        link_context = 'object in context'
      when 'info:eu-repo/semantics/objectFile' #raw object        
        link_context = 'raw object'        
      end                
      
      if link_context.size > 0
        url = item.xpath('.//didl:Component/didl:Resource', 'didl' => 'urn:mpeg:mpeg21:2002:02-DIDL-NS')[0].attribute('ref')
        url = url.nil? ? '' : url.value           
        availability = item.xpath('.//didl:Component/didl:Resource', 'didl' => 'urn:mpeg:mpeg21:2002:02-DIDL-NS')[0].attribute('kulAvailability')
        availability = availability.nil? ? 'public' : availability.value 

        links << {link_context => {"value" => url, 
                                   "availability" => availability}}
        
      end
      
    end      

    links_str = ''
    links.each do |link|
      access = link.keys[0]
      availability = link.values[0]['availability'] || 'public'
      value = link.values[0]['value']
      
      links_str += "<url access='#{access}' availability='#{availability}'>#{value}</url>"
    end

    mods.children.last.after("<location>#{links_str}</location>")    
    
    mods
  end
  
  def save(mods, identifier, datestamp, i)
      oai_pmh = <<OAI
<?xml version = "1.0" encoding = "UTF-8"?>
<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
  <responseDate>#DATESTAMP#</responseDate>
  <request>didl</request>
  <ListRecords>
    <record>
      <header>
        <identifier>#IDENTIFIER#</identifier>
        <datestamp>#DATESTAMP#</datestamp>
      </header>
      <metadata>             
      </metadata>
    </record>
  </ListRecords>
</OAI-PMH>
OAI

#    File.open("#{ConfigFile[:staging_dir]}/mods_#{i}.xml", 'w') do |f|
#      f.puts mods
#    end

    pnx = Mods.new(identifier, Nokogiri::XML(mods.to_s))
    oai_pmh.gsub!('#IDENTIFIER#', identifier)
    oai_pmh.gsub!('#DATESTAMP#', datestamp)  

    oai = Nokogiri::XML(oai_pmh)
    oai.at('metadata').add_child(pnx.parse.root)

    File.open("#{ConfigFile[:staging_dir]}/dspace_#{i}.xml", 'w') do |f|
      f.puts oai.to_s
    end  

  end  
end
