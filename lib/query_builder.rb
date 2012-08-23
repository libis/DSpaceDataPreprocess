module QueryBuilder
  Dir.glob("#{File.split(__FILE__)[0]}/query_builder/**/*.rb").each do |r|
    rr = r.split('query_builder/')[1].gsub('.rb','')
    require "query_builder/#{rr}"
  end
end