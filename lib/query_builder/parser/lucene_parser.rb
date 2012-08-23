require 'iconv'

class LuceneParser
  INDEXES = %w(sys any title author subject library collection callnumber year isbn issn resource_type acq_date acq_method acq_local acq_source)

=begin
    INDEXES = ['any',
               'addtitle',
               'alttitle',
               'cdate',
               'creator',
               'desc',
               'ftext',
               'general',
               'init',
               'isbn',
               'issn',
               'lastmodified',
               'popularity',
               'rec_cdate',
               'rid',
               'rtype',
               'scdate',
               'scope',
               'sid',
               'subject',
               'title',
               'facet_creationdate',
               'facet_creator',
               'facet_domain',
               'facet_fmt',
               'facet_frbrgroupid',
               'facet_frbrtype',
               'facet_genre',
               'facet_lang',
               'facet_library',
               'facet_local1',
               'facet_pfilter',
               'facet_rtype',
               'facet_tlevel',
               'facet_topic']
=end

  def initialize
    @open_bracket = 0
    @close_bracket = 0

  end

  def available_indexes
    INDEXES
  end

  def parse(query_tokens)
    tokens = tokenize(query_tokens)

    queries = []
    query   = {:index => 'any', :match => 'contains', :term => ''}
    tokens.each do |t|
      if is_index?(t)

        if @open_bracket == @close_bracket
          queries << query unless query[:term].empty?
        else
          raise "query error: brackets do not match"
        end
        query   = {:index => 'any', :match => 'contains', :term => ''}


        query[:index] = t.chop
      elsif is_operator?(t)
        query[:term] += " " if query[:term].size > 0
        query[:term] += "#{t}"
      elsif is_term?(t)
        if t[0].chr.eql?('^') && query[:term].size == 0
          query[:match] = 'begins_with'
          t.slice!(0)
        end

        query[:term] += " " if query[:term].size > 0
        query[:term] += "#{t}"
      else
        puts t
      end
    end

    if @open_bracket == @close_bracket
      queries << query unless query[:term].empty?
    else
      raise "query error: brackets do not match"
    end

    queries
  end

  private
  def determine_charset(query)
    result = 'utf-8'
    char_values = query.bytes.to_a
    flag = 0
    char_values.each do |c|
      if c > 127
        flag += 1
      else
        flag = 0
      end

      if flag == 2
        result = 'utf-8'
      elsif flag == 1
        result = 'iso-8859-1'
      end
    end

    result
  end

  def tokenize(query)
    charset = determine_charset(query)
    query = Iconv.conv('utf-8', charset, query) # normalize
    query.gsub!(/\b *?: *?/, ": ") # remove
    query.gsub!(/ {1,}/,' ')
    query.split(' ')
  end

  def is_index?(possible_index)
    if possible_index[-1].chr.eql?(':')
      return INDEXES.include?(possible_index.gsub(':',''))
    end
    return false
  end

  def is_term?(possible_term)
    return false if possible_term.nil?
    return false if is_operator?(possible_term)

    @open_bracket += possible_term.scan(/\(|\[|\"|\'/).size || 0
  @close_bracket += possible_term.scan(/\)|\]|\"|\'/).size || 0
  true
end

def is_operator?(possible_operator)
  #TODO: check if NEAR is supported. Lucene supports it
  operators = %w(AND OR NOT)
  operators.include?(possible_operator)
end
end
