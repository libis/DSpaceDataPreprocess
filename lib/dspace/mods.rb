require 'rubygems'
require 'isbn/tools'
require 'logger'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'cgi'

#require 'query_builder'
#require 'x_service'
require 'dspace/mods_constants'
require 'pp'


class Mods
  include Constants

  attr_reader :raw, :xml, :data, :identifier, :logger

  def initialize(identifier, filename_or_record)
    @logger = Logger.new("#{ConfigFile[:log_dir]}/error.log")
    @identifier = identifier
    @data = { :control => {},
      :display => {},
      :links   => {},
      :search  => {},
      :facets  => {},
      :sort    => {},
      :addata  => {}
    }


    if filename_or_record.class.to_s.eql?('String')
      @raw = Nokogiri::XML(open(filename_or_record))
    elsif filename_or_record.class.to_s.match(/Nokogiri/)
      @raw = filename_or_record
    else
      puts "only nokogiri supported as an XML parser"
      puts "class = #{filename_or_record.class.to_s}"
      exit 1
    end
  end

  def parse
    display_type
    display_title_vertitle_unititle
    display_creator_contributor_lds02_relation
    display_genre
    display_creationdate_publisher_edition
    display_language
    display_format
    display_description
    display_coverage
    display_identifiers
    display_identifier_ispartof_relation
    display_identifier_pmid
    links_backlink
    links_fulltext
    search_subject
    search_status
    sort_dates
    facet_toplevel
    links_addlink_unumber
    links_addlink
    
    build_pnx
  end

  private

  def links_addlink_unumber    
    #Create entries for U-number
    name = @raw.xpath('/mods:mods/mods:name', {"mods" => "http://www.loc.gov/mods/v3"})
    
    name.each do |n|
      unless n.nil? || n.attribute('ID').nil?
        uid = n.attribute('ID').text
        unless uid.empty?
          given  = n.css('namePart[type="given"]').text
          family = n.css('namePart[type="family"]').text
          store(:links, :addlink, "$$D#{family}, #{given}$$Uhttp://www.kuleuven.be/wieiswie/nl/person/#{uid.downcase}")
          store(:search, :description, uid.downcase)
        end
      end
    end
       
  end


  def links_addlink
    retrieve(:display, :identifier).each do |d|
      if d.match('ISBN')
        isbn_match = d.match(/^\$\$CISBN:\$\$V(.*$)/)
        unless isbn_match.nil?
          isbn = isbn_match[1]      
            if is_isbn_present_in_limo?(isbn)
              store(:links, :addlink, "$$DFind print copy$$TISBN_SEARCH")
            end       
        end
      end
    end    
  end

  def display_type
    type_of_resource = @raw.xpath('//mods:typeOfResource', {"mods" => "http://www.loc.gov/mods/v3"})
    type_of_resource.each do |t|
      if MAP_TYPE_OF_RESOURCE.include?(t.text)
        store(:display, :type, MAP_TYPE_OF_RESOURCE[t.text])
      end
    end
  end

  def display_title_vertitle_unititle
    title_info = @raw.xpath('/mods:mods/mods:titleInfo', {"mods" => "http://www.loc.gov/mods/v3"})
    title_info.each do |t|
      title = []
      title << t.css('nonSort').text
      title << t.css('title').text
      title << t.css('subTitle').text
      title << t.css('partNumber').text
      title << t.css('partName').text

      title.compact!
      title.delete_if {|x| x.length == 0}

      if t.has_attribute?('type')
        case t.attribute('type').text
        when "abbreviated"
          store(:display, :title, "Abbreviated title : #{title.join(' ')}")
        when "translated"
          store(:display, :vertitle, title.join(' '))
        when "alternative"
          store(:display, :vertitle, title.join(' '))
        when "uniform"
          store(:display, :unititle, title.join(' '))
        else
          store(:display, :title, title.join(' '))
        end
      else
        store(:display, :title, title.join(' '))
      end
    end
  end

  def display_creator_contributor_lds02_relation
    name = @raw.xpath('/mods:mods/mods:name', {"mods" => "http://www.loc.gov/mods/v3"})
    name.each do |n|
      case n.attribute('type').text
      when 'personal'
        if n.css('roleTerm[authority="marcrelator"][type="code"]').text.eql?('aut')
          creator = {}
          creator.store(:given, n.css('namePart[type="given"]').text)
          creator.store(:family, n.css('namePart[type="family"]').text)
          creator.store(:role, "[#{MAP_MARC_RELATOR_CODE[n.css('roleTerm[authority="marcrelator"][type="code"]').text]}]")

          store(:display, :creator, {:personal => creator})
        elsif ['ths', 'edt', 'oth'].include?(n.css('roleTerm[authority="marcrelator"][type="code"]').text)
          contributor = {}
          contributor.store(:given, n.css('namePart[type="given"]').text)
          contributor.store(:family, n.css('namePart[type="family"]').text)
          contributor.store(:role, "#{MAP_MARC_RELATOR_CODE[n.css('roleTerm[authority="marcrelator"][type="code"]').text]}")

          store(:display, :contributor, {:personal => contributor})
        else
          @logger.warn("GENRE: not mapped => #{n.css('roleTerm[authority="marcrelator"][type="code"]').text}")
        end
      when 'corporate'
        creator = []
        creator << n.css('namePart').text

        creator.compact!
        creator.delete_if {|x| x.length == 0}
        store(:display, :creator, {:corporate => creator.join(' ')})
      when 'conference'
        conference = []
        conference << n.css('namePart:not([type])').text
        conference << "Date: #{n.css('namePart[type="date"]').text}" if n.css('namePart[type="date"]').text.size > 0
        conference << "Edition: #{n.css('namePart[type="edition"]').text}" if n.css('namePart[type="edition"]').text.size > 0
        conference << "Location: #{n.css('namePart[type="location"]').text}" if n.css('namePart[type="location"]').text.size > 0

        conference.compact!
        conference.delete_if {|x| x.length == 0}
        store(:display, :lds02, conference.join(', '))
        store(:display, :relation, conference.join(', '))
      end
    end
  end

  def display_genre
    genre = @raw.xpath('/mods:mods/mods:genre[@authority="K.U.Leuven"]', {"mods" => "http://www.loc.gov/mods/v3"})
    genre.each do |g|
      store(:display, :genre, MAP_EU_REPO[g.text])
      store(:control, :originaltype, g.text)
    end
  end

  def display_creationdate_publisher_edition
    origin_info = @raw.xpath('/mods:mods/mods:originInfo', {"mods" => "http://www.loc.gov/mods/v3"})
    origin_info.each do |o|
      store(:display, :creationdate, o.css('dateIssued[encoding="iso8601"]').text)
      publisher_and_location = "#{o.css('publisher').text}"
      publisher_and_location += " (#{o.css('place placeTerm[type=\'text\']').text})" if o.css('place placeTerm[type=\'text\']').text.size > 0

      store(:display, :publisher, publisher_and_location)
      store(:display, :edition, o.css('edition').text)
    end
  end

  def display_language
    language = @raw.xpath('/mods:mods/mods:language', {"mods" => "http://www.loc.gov/mods/v3"})
    language.each do |l|
      tl = l.css('languageTerm[type="code"]').text.downcase.split('-')
      if tl.class.to_s.eql?('Array')
        store(:display, :language, MAP_ISO6391_ISO6392[tl[0]])
      end
    end
  end

  def display_format
    physical_desciption = @raw.xpath('/mods:mods/mods:physicalDescription', {"mods" => "http://www.loc.gov/mods/v3"})
    physical_desciption.each do |p|
      pd = []
      pd << p.css('form').text
      pd << p.css('note').text
      pd << p.css('extent').text

      pd.compact!
      pd.delete_if {|x| x.length == 0}

      store(:display, :format, pd.join(' '))
    end
  end

  def display_description
    description       = @raw.xpath('/mods:mods/mods:description', {"mods" => "http://www.loc.gov/mods/v3"})
    description.each do |d|
      store(:display, :description, d.text)
    end

    abstract          = @raw.xpath('/mods:mods/mods:abstract', {"mods" => "http://www.loc.gov/mods/v3"})
    abstract.each do |a|
      store(:display, :description, a.text)
    end

    note              = @raw.xpath('/mods:mods/mods:note', {"mods" => "http://www.loc.gov/mods/v3"})
    note.each do |n|
      if n.attribute('type').text.eql?('status')
        store(:display, :description, "<br><br>Publication Status: #{n.text}")
      else
        store(:display, :description, n.text)
      end
    end
  end

  def sort_dates
    dates = {}
    origin_info = @raw.xpath('/mods:mods/mods:originInfo', {"mods" => "http://www.loc.gov/mods/v3"})
    origin_info.each do |o|
      dates.store("available", Time.parse(o.css('dateCreated[encoding="iso8601"]').text).strftime('%Y-%m-%d')) if o.css('dateCreated[encoding="iso8601"]').text.size > 0
      dates.store("accessioned", Time.parse(o.css('dateOther[encoding="iso8601"]').text).strftime('%Y-%m-%d')) if o.css('dateOther[encoding="iso8601"]').text.size > 0
    end
    store(:sort, :dates, dates)
  end


  def display_coverage
    table_of_contents = @raw.xpath('/mods:mods/mods:tableOfContents', {"mods" => "http://www.loc.gov/mods/v3"})
    table_of_contents.each do |t|
      toc = t.text.gsub(/\r|\n/, "<br>")
      store(:display, :coverage, toc)
    end
  end

  def display_identifiers
    identifiers =  @raw.xpath('/mods:mods/mods:identifier', {"mods" => "http://www.loc.gov/mods/v3"})
    identifiers.each do |i|
      if !i.is_a?(String)
        case i.attribute('type').text
        when 'uri'
          if i.text.match(/^URN:ISSN:/)
            issn = i.text.match(/^URN:ISSN:(.*$)/)[1]
            store(:display, :identifier, "$$CISSN:$$V#{issn}")
          elsif i.text.match(/^URN:ISBN:/)
            isbn = i.text.match(/^URN:ISBN:(.*$)/)[1]
            store(:display, :identifier, "$$CISBN:$$V#{isbn}")
          elsif i.text.match(/^http/)
            store(:links, :linktorsrc, "$$U#{i.text}")
          end
        when 'issn'
          store(:display, :identifier, "$$CISSN:$$V#{i.text}")
        when 'isbn'
          store(:display, :identifier, "$$CISBN:$$V#{i.text}")
        end
      end
    end
  end


  def display_identifier_ispartof_relation
    related_item      = @raw.xpath('/mods:mods/mods:relatedItem', {"mods" => "http://www.loc.gov/mods/v3"})
    related_item.each do |r|
      identifier = r.css('identifier')

      identifier.each do |i|
        case i.attribute('type').text
        when 'uri'
          if i.text.match(/^URN:ISSN:/)
            issn = i.text.match(/^URN:ISSN:(.*$)/)[1]
            store(:display, :identifier, "$$CISSN:$$V#{issn}")
          elsif i.text.match(/^URN:ISBN:/)
            isbn = i.text.match(/^URN:ISBN:(.*$)/)[1]
            store(:display, :identifier, "$$CISBN:$$V#{isbn}")
          elsif i.text.match(/^http/)
            store(:links, :linktorsrc, "$$U#{i.text}")
          end
        when 'issn'
          store(:display, :identifier, "$$CISSN:$$V#{i.text}")
        when 'isbn'
          store(:display, :identifier, "$$CISBN:$$V#{i.text}")
        end
      end

      ispartof = { :title  => "#{r.css('titleInfo title').text}",
        :volume => "#{r.css('part detail[type="volume"] number').text}",
        :issue  => "#{r.css('part detail[type="issue"] number').text}",
        :pages  => {:start => "#{r.css('part extent[unit="page"] start').text}",
        :end   => "#{r.css('part extent[unit="page"] end').text}"},
        :chapter => "#{r.css('part detail[type="chapter"] number').text}",
        :article_number => "#{r.css('part detail:not([type]) number').text}"
      }

      store(:display, :ispartof, ispartof)
      #  store(:display, :relation, ispartof[:title])
    end
  end

  def display_identifier_pmid
    pmid = @raw.xpath('/mods:mods/mods:identifier[@type="pmid"]', {"mods" => "http://www.loc.gov/mods/v3"})
    pmid.each do |p|
      store(:display, :identifier, "$$CPMID:$$V#{p.text}")
    end
  end

  def links_backlink
    backlinks = @raw.xpath('/mods:mods/mods:location/mods:url[@access = "object in context" and @availability != "private"]', {"mods" => "http://www.loc.gov/mods/v3"}) || []
    backlinks.each do |backlink|
      #      if backlink.attribute('availability').text.eql?('public')
      #        backlink_text = "Document freely available"
      #      else
      #        backlink_text = "Document available via K.U.Leuven Intranet"
      #      end
      #      store(:links, :backlink, "$$U#{backlink.text}$$D#{backlink_text}")
      store(:links, :backlink, "$$U#{backlink.text}$$Ebacklink_lirias")
    end
  end

  def links_fulltext
    fulltextlinks = @raw.xpath('/mods:mods/mods:location/mods:url[@access = "raw object" and @availability != "private"]', {"mods" => "http://www.loc.gov/mods/v3"}) || []
    fulltextlinks.each do |fulltextlink|
      if fulltextlink.attribute('availability').text.eql?('public')
        fulltextlink_text = "Document freely available"
      else
        fulltextlink_text = "Document available via K.U.Leuven Intranet"
      end
      store(:links, :linktorsrc, "$$U#{fulltextlink.text}$$D#{fulltextlink_text}")
    end
  end

  def search_subject
    subject = @raw.xpath('/mods:mods/mods:subject/*', {"mods" => "http://www.loc.gov/mods/v3"})
    subject.each do |s|
      store(:search, :subject, s.text)
    end
  end

  def search_status
    status = @raw.xpath('/mods:mods/mods:note[@type="status"]', {"mods" => "http://www.loc.gov/mods/v3"})
    status.each do |s|
      store(:search, :status, s.text)
    end
  end

  def facet_toplevel
    genre = @raw.xpath('/mods:mods/mods:genre[@authority="K.U.Leuven"]', {"mods" => "http://www.loc.gov/mods/v3"})
    genre.each do |t|
      if t.text.eql?('IT')
        store(:facets, :toplevel, 'peer_reviewed')
      end
    end

    #online_resources
  end

  def build_pnx
    File.open("#{ConfigFile[:log_dir]}/identifiers.log", "a") do |f|
      f.puts @identifier
    end
    pnx = Nokogiri::XML::Builder.new do |xml|
      xml.record("id" => "#{@identifier.split(':').last}") do
        xml.lbs_control do
          xml.lbs_sourcerecordid(@identifier.split(':').last)
          xml.lbs_sourceid('LIRIAS')
          xml.lbs_originalsourceid('LIRIAS')
          xml.lbs_sourceformat('MODS')
          xml.lbs_sourcesystem('Other')
          retrieve(:control, :originaltype).each do |d|
            xml.lbs_originaltype(d)
          end
        end #control

        xml.lbs_display do
          types = retrieve(:display, :genre)
          types = retrieve(:display, :type) if types.size == 0
          types.each do |d|
            xml.lbs_type(d)
          end

          xml.lbs_source('LIRIAS')

          retrieve(:display, :title).each do |d|
            xml.lbs_title(d)
          end

          retrieve(:display, :unititle).each do |d|
            xml.lbs_unititle(d)
          end

          retrieve(:display, :vertitle).each do |d|
            xml.lbs_vertitle(d)
          end

          creators = []
          retrieve(:display, :creator).each do |d|
            d.each do |k,v|
              if k.to_s.eql?('personal')
                creators << "#{v[:family]}, #{v[:given]}"
              elsif k.to_s.eql?('corporate')
                creators << v
              end
            end
          end
          xml.lbs_creator(creators.join(' ; '))

          contributors = []
          retrieve(:display, :contributor).each do |d|
            d.each do |k,v|
              if k.to_s.eql?('personal')
                contributors << "#{v[:family]}, #{v[:given]} (#{v[:role]})"
              end
            end
          end
          xml.lbs_contributor(contributors.join(' ; '))

          retrieve(:display, :lds02).each do |d|
            xml.lbs_lds02(d)
          end

          retrieve(:display, :relation).each do |d|
            xml.lbs_relation(d)
          end

          retrieve(:display, :genre).each do |d|
            xml.lbs_genre(d)
          end

          retrieve(:display, :creation).each do |d|
            xml.lbs_creationdate(d)
          end

          retrieve(:search, :subject).each do |d|
            xml.lbs_subject(d)
          end

          retrieve(:display, :publisher).each do |d|
            xml.lbs_publisher(d)
          end

          retrieve(:display, :edition).each do |d|
            xml.lbs_edition(d)
          end

          retrieve(:display, :language).each do |d|
            xml.lbs_language(d)
          end

          retrieve(:display, :format).each do |d|
            xml.lbs_format(d)
          end

          retrieve(:display, :description).each do |d|
            unless d.is_a?(String)
              d.each do |description|
                xml.lbs_description(description)
              end
            else
              xml.lbs_description(d)
            end
          end

          retrieve(:display, :coverage).each do |d|
            xml.lbs_coverage(d)
          end

          retrieve(:display, :identifier).each do |d|
            xml.lbs_identifier(d)
          end

          retrieve(:display, :ispartof).each do |d|
            ispartof = []
            ispartof_title = "#{d[:title]}:" if d[:title].size > 0
            date = retrieve(:display, :creationdate)[0]

            ispartof << date unless date.nil?
            ispartof << "Volume: #{d[:volume]}" if d[:volume].size > 0
            ispartof << "Issue: #{d[:issue]}" if d[:issue].size > 0
            ispartof << "Chapter: #{d[:chapter]}" if d[:chapter].size > 0
            ispartof << "Pages: #{d[:pages][:start]}-#{d[:pages][:end]}" if d[:pages][:end].size > 0
            ispartof << "Article: #{d[:article_number]}" if d[:article_number].size > 0

            ispartof.compact!
            ispartof.delete_if{|x| x.length == 0}

            xml.lbs_ispartof("#{ispartof_title} #{ispartof.join(', ')}")
          end
        end #display

        # find out if record has fulltext in SFX -- START
        has_fulltext = false

        issn = nil
        retrieve(:display, :identifier).each do |d|
          if d.match('ISSN')
            issn_match = d.match(/^\$\$CISSN:\$\$V(.*$)/)
            unless issn_match.nil?
              issn = issn_match[1]
            else
              @logger.warn("#{@identifier} bad ISSN : #{d}")
            end
          end
        end

        creationdates = retrieve(:display, :creationdate)
        unless issn.nil? || creationdates.empty?
          creationdate = creationdates[0].split(/[-\/]/)
          year = creationdate.map{ |c| c if c.size==4}
          unless year.empty?
            has_fulltext = !get_available(issn, year[0]).nil?
          end
        end
        # find out if record has fulltext in SFX -- STOP

        xml.lbs_links do
          retrieve(:links, :linktorsrc).each do |d|
            xml.lbs_linktorsrc(d)
          end

          retrieve(:links, :backlink).each do |d|
            xml.lbs_backlink("#{d}")
          end

          retrieve(:links, :fulltext).each do |d|
            xml.lbs_linktorsrc(d)
          end

          retrieve(:links, :addlink).each do |d|
            xml.lbs_addlink(d)
          end

        end #links

        xml.lbs_search do
          creator_contrib = retrieve(:display, :creator) + retrieve(:display, :contributor)
          creator_contrib.each do |d|
            d.each do |k,v|
              if k.to_s.eql?('personal')
                xml.lbs_creatorcontrib("#{v[:family]}, #{v[:given]}")
              elsif k.to_s.eql?('corporate')
                xml.lbs_creator(v)
              end
            end
          end

          retrieve(:display, :title).each do |d|
            xml.lbs_title(d)
          end

          retrieve(:display, :vertitle).each do |d|
            xml.lbs_title(d)
          end

          retrieve(:display, :unititle).each do |d|
            xml.lbs_title(d)
          end

          retrieve(:display, :relation).each do |d|
            xml.lbs_addtitle(d)
          end

          retrieve(:display, :description).each do |d|
            xml.lbs_description(d)
          end

          retrieve(:search, :description).each do |d|
            xml.lbs_description(d)
          end

          retrieve(:search, :subject).each do |d|
            xml.lbs_subject(d)
          end


          types = retrieve(:display, :genre)
          types = retrieve(:display, :type) if types.size == 0
          types.each do |d|
            xml.lbs_rsrctype(d)
          end

          retrieve(:display, :creationdate).each do |d|
            xml.lbs_creationdate(d)
          end

          retrieve(:display, :identifier).each do |d|
            if d.match('ISSN')
              issn_match = d.match(/^\$\$CISSN:\$\$V(.*$)/)
              unless issn_match.nil?
                issn = issn_match[1]
                xml.lbs_issn(issn)
              else
                @logger.warn("#{@identifier} bad ISSN : #{d}")
              end
            elsif d.match('ISBN')
              isbn_match = d.match(/^\$\$CISBN:\$\$V(.*$)/)
              unless isbn_match.nil?
                isbn = isbn_match[1]

                isbn_original = isbn_match[1]
                                
                isbn = ISBN_Tools.cleanup(isbn_original)
                if ISBN_Tools.is_valid?(isbn)
                  xml.lbs_isbn(isbn_original)                  
                  xml.lbs_isbn(isbn)
                                   
                  if isbn.size == 10
                    isbn13 = ISBN_Tools.isbn10_to_isbn13(isbn)
                    unless isbn13.nil?
                      xml.lbs_isbn(isbn13)
                      isbn13_h = ISBN_Tools.hyphenate_isbn13(isbn13)
                      xml.lbs_isbn(isbn13_h) unless isbn13_h.nil?
                    end
                  elsif isbn.size == 13
                    isbn10 = ISBN_Tools.isbn13_to_isbn10(isbn)
                    unless isbn10.nil?
                      xml.lbs_isbn(isbn10)
                      isbn10_h = ISBN_Tools.hyphenate_isbn10(isbn10)
                      xml.lbs_isbn(isbn10_h) unless isbn10_h.nil?
                    end                    
                  end
                end
                
=begin                
                isbn = isbn_original.gsub(/\s|-/,'')

                if ISBN.valid?(isbn)
                  xml.lbs_isbn(ISBN.thirteen(isbn)) if isbn.size != 13
                  xml.lbs_isbn(ISBN.ten(isbn)) if isbn.size != 10 || !isbn.eql?(isbn_original)
                else
                  xml.lbs_isbn(isbn)
                end
=end                
              else
                @logger.warn("#{@identifier} bad ISBN : #{d}")
              end
            end
          end


          xml.lbs_status(retrieve(:search, :status)[0])
        end #search

        xml.lbs_facets do
          retrieve(:display, :genre).each do |d|
            xml.lbs_rsrctype(d)
          end

          retrieve(:display, :language).each do |d|
            xml.lbs_language(d)
          end

          retrieve(:display, :creationdate).each do |d|
            xml.lbs_creationdate(d)
          end

          creator_contrib = retrieve(:display, :creator) + retrieve(:display, :contributor)
          creator_contrib.each do |d|
            d.each do |k,v|
              if k.to_s.eql?('personal')
                xml.lbs_creatorcontrib("#{v[:family]}, #{v[:given]}")
              elsif k.to_s.eql?('corporate')
                xml.lbs_creatorcontrib(v)
              end
            end
          end

          retrieve(:control, :originaltype).each do |d|
            if ['IT', 'IC', 'IHb', 'IBa', 'IBe'].include?(d)
              xml.lbs_international_publications('international_publication')
            end
          end

          retrieve(:search, :subject).each do |d|
            xml.lbs_topic(d)
          end



#          retrieve(:display, :type).each do |d|
#            xml.lbs_rsrctype(d)
#          end

          toplevel = nil
          if retrieve(:facets, :toplevel).size > 0
            toplevel = retrieve(:facets, :toplevel)[0]
            xml.lbs_toplevel(toplevel) unless toplevel.nil?
          end

          toplevel = nil
          #if retrieve(:links, :fulltext).size > 0
          if has_fulltext
            xml.lbs_toplevel('online_resources')
          end

        end # facets

        xml.lbs_sort do
          retrieve(:display, :creationdate).each do |d|
            xml.lbs_creationdate(d)
          end
        end #sort

        issn = nil
        retrieve(:display, :identifier).each do |d|
          if d.match('ISSN')
            issn_match = d.match(/^\$\$CISSN:\$\$V(.*$)/)
            unless issn_match.nil?
              issn = issn_match[1]
            else
              @logger.warn("#{@identifier} bad ISBN : #{d}")
            end
          end
        end

        xml.lbs_delivery do
          xml.lbs_institution('KUL')

          if @raw.xpath('/mods:mods/mods:location/mods:url[@access="raw object" and @availability != "private"]', {"mods" => "http://www.loc.gov/mods/v3"}).size > 0
            xml.lbs_delcategory('Online Resource')
          else
            xml.lbs_delcategory('Remote Search Resource')
          end


          if @raw.xpath('/mods:mods/mods:location/mods:url[@availability != "public"]', {"mods" => "http://www.loc.gov/mods/v3"}).size > 0 
          #if @raw.xpath('/mods:mods/mods:location/mods:url[@availability != "public"]', {"mods" => "http://www.loc.gov/mods/v3"}).size > 0 && has_fulltext
            xml.lbs_resdelscope('LIRIAS')
          elsif has_fulltext
            xml.lbs_fulltext('fulltext')
          else
            xml.lbs_fulltext('no_fulltext')
          end
        end #delivery

        xml.lbs_addata do
          d = retrieve(:display, :creator).first
          unless d.nil?
            d.each do |k,v|
              if k.to_s.eql?('personal')
                xml.lbs_aulast(v[:family])
                xml.lbs_aufirst(v[:given])
                xml.lbs_au("#{v[:family]}, #{v[:given]}")
              elsif k.to_s.eql?('corporate')
                xml.lbs_aucorpr(v)
              end
            end
          end

          has_IS = ''
          retrieve(:display, :identifier).each do |d|
            if d.match('ISSN')
              issn_match = d.match(/^\$\$CISSN:\$\$V(.*$)/)
              unless issn_match.nil?
                issn = issn_match[1]
                xml.lbs_issn(issn)
                has_IS = 'ISSN'
              else
                @logger.warn("#{@identifier} bad ISBN : #{d}")
              end
            elsif d.match('ISBN')
              isbn_match = d.match(/^\$\$CISBN:\$\$V(.*$)/)
              unless isbn_match.nil?
                isbn = isbn_match[1]
                xml.lbs_isbn(isbn)
                has_IS = 'ISBN'
              else
                @logger.warn("#{@identifier} bad ISBN : #{d}")
              end
              xml.lbs_btitle(retrieve(:display, :title).first)
            end
          end

          genre = retrieve(:display, :genre).first

          if ['article'].include?(genre) || has_IS.eql?('ISSN')
            xml.lbs_atitle(retrieve(:display, :title).first)
            ispartof = retrieve(:display, :ispartof).first
            unless ispartof.nil?
              xml.lbs_jtitle(ispartof[:title])
              xml.lbs_volume(ispartof[:volume])
              xml.lbs_issue(ispartof[:issue])
              xml.lbs_spage(ispartof[:pages][:start])
              xml.lbs_epage(ispartof[:pages][:end])
              xml.lbs_pages("#{ispartof[:pages][:start]}-#{ispartof[:pages][:end]}")
            end
          end

          xml.lbs_genre(genre)
          xml.lbs_date(retrieve(:display, :creationdate).first)
        end #addata


      end #record
    end # pnx

    Nokogiri::XML(pnx.to_xml)
  end

  def store(section, field, data)
    if @data.include?(section)
      section_values = @data[section]
      if section_values.include?(field)
        field_values = section_values[field]
      else
        field_values = []
      end

      field_values << data

      section_values.store(field, field_values)
      @data.store(section, section_values)
    else
      puts "section '#{section.to_s}' not found"
      exit 1
    end
  end

  def retrieve(section, field)
    if @data.include?(section)
      section_values = @data[section]
      if section_values.include?(field)
        return section_values[field]
      else
        return []
      end
    else
      puts "section '#{section.to_s}' not found"
      exit 1
    end
  end

  def get_available(issn, year)
    url = URI.parse(ConfigFile[:sfx][:rsi])
    #    url = URI.parse("http://sfx.libis.be/sfxlcl3/cgi/core/rsi/rsi.cgi")
    http = Net::HTTP.new(url.host, url.port)
    #  http.set_debug_output($stdout)

    xml_request = <<XML
<?xml version="1.0" ?>
<ISSN_REQUEST VERSION="1.0" xsi:noNamespaceSchemaLocation="ISSNRequest.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <ISSN_REQUEST_ITEM>
    <ISSN>#{issn}</ISSN>
    <YEAR>#{year}</YEAR>
    <INSTITUTE_NAME>KULeuven</INSTITUTE_NAME>
  </ISSN_REQUEST_ITEM>
</ISSN_REQUEST>
XML

    xml_request.gsub!("\n")
    #<ISSN_RESPONSE_DETAILS AVAILABLE_SERVICES="getFullTxt" PEER_REVIEWED="YES" RESULT="Found"/>
    request_url = "#{url.request_uri}?request_xml=#{CGI::escape(xml_request)}"
    request = Net::HTTP::Get.new(request_url)

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      xml = Nokogiri::XML(response.body)
      details = xml.xpath('//ISSN_RESPONSE_DETAILS')

      if details.size > 0 && details.attr('RESULT').value.eql?('Found')
        available_services = details.attr('AVAILABLE_SERVICES').nil? ? '' : details.attr('AVAILABLE_SERVICES').value
        peer_reviewed      = details.attr('PEER_REVIEWED').nil? ? false : details.attr('PEER_REVIEWED').value.eql?('YES') ? true : false

        return {:peer_reviewed => peer_reviewed, :services => available_services}
      end

    else
      response.error!
    end

    return nil
  rescue Exception => e
    puts "#{e.message}"
  end

  def is_isbn_present_in_limo?(isbn)
    num_records = 0
    query_uris = []
    factory = QueryBuilder::Factory.new(:lucene, :primo_rest)
    query_uris << factory.build("isbn:#{isbn} resource_type:book", {:host => 'limo.libis.be', :institution => 'KUL'})
    query_uris << factory.build("isbn:#{isbn.gsub('-','')} resource_type:book", {:host => 'limo.libis.be', :institution => 'KUL'})

    unless query_uris.empty?
      query_uris.each do |query_uri|
#        @logger.info(query_uri)
        xservice = XService.new
        xservice.error_handler = Proc.new do |context|
          unless context.result.css('ERROR').size == 0
            error_text = context.result.css('ERROR').first.attr('MESSAGE')
            error_code = context.result.css('ERROR').first.attr('CODE')
            raise "#{error_text}"
          end
        end

        result = xservice.query(query_uri, :query_timeout => 7)
        unless result.nil?
          document_set = result.xpath('//sear:DOCSET', {'sear' => "http://www.exlibrisgroup.com/xsd/jaguar/search"})
          if document_set.attr('TOTALHITS').value.to_i > 0
            num_records = document_set.attr('TOTALHITS').value.to_i
          end
        end
	     break if num_records > 0
      end
    end
#    puts "\t\t#{num_records}"
    num_records > 0
  rescue Exception => e
    puts e.message
    return 0
  end
end
