#!/usr/bin/env ruby

# This is a very ugly, quickly written script
# it generates a domain.lisp file for a provided sparql endpoint and graph

require 'linkeddata'
require 'optparse'
require 'erb'
require 'ostruct'

# options
@options = { endpoint: nil, graph: nil, base: nil }
opt_parser = OptionParser.new do |opts|
  opts.on("-b", "--base-iri BASE", "base iri (required)") do |b|
    @options[:base] = b.end_with?('/') ? b : "#{b}/"
  end
  opts.on("-e", "--endpoint ENDPOINT", "endpoint (required)") do |e|
    @options[:endpoint] = e
  end
  opts.on("-g", "--graph GRAPH", "graph") do |e|
    @options[:graph] = e
  end
  opts.on('-h', '--help', 'help') do
    puts opt_parser
    exit
  end
end

opt_parser.parse!

if @options[:endpoint].nil? || @options[:base].nil?
  puts opt_parser
  exit -1
end

# helpers
class String
  def kebab_case
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    tr("_", "-").
    downcase
  end
end


def select(select, where)
  client = SPARQL::Client.new(@options[:endpoint])
  if @options[:graph]
    client.query "SELECT #{select} FROM <#{@options[:graph]}> WHERE { #{where} }"
  else 
    client.query "SELECT #{select} WHERE { #{where} }"
  end
end

def iri_to_name(iri)
  return if iri.nil?
  if iri.rindex('#')
    iri.slice(iri.rindex('#')+1,iri.size).kebab_case
  else
    iri.slice(iri.rindex('/')+1,iri.size).kebab_case
  end
end

def type_to_resource_type(iri)
  if iri.rindex('#')
    iri.slice(iri.rindex('#')+1,iri.size).downcase
  else
    iri.slice(iri.rindex('/')+1,iri.size).downcase
  end
end

# build data
classes = Hash[ select("distinct ?class as ?c", "[] a ?class").map{|x| [x[:c].value, {properties: nil, relations: nil, inverse_relations: nil}] } ]

classes.each do |klass,c|
  c[:name] = iri_to_name(klass)
  c[:properties] = select("distinct ?prop ?dType", "?s a <#{klass}>; ?prop ?value. FILTER(isLiteral(?value)) BIND(datatype(?value) as ?dType)").map do |x|
    {
      predicate: x[:prop].value,
      type: type_to_resource_type(x[:dType] ? x[:dType].value : "http://www.w3.org/2001/XMLSchema#string"),
      name: iri_to_name(x[:prop].value)
    }
  end
  c[:relations] =  select("distinct ?prop ?type", "?s a <#{klass}>; ?prop ?value. ?value a ?type  FILTER(isIri(?value))").map do |x|
    {
      predicate: x[:prop].value,
      as: iri_to_name(x[:prop].value),
      name: iri_to_name(x[:type].value)
    }
  end
  c[:inverse_relations] =  select("distinct ?prop ?type", "?s a <#{klass}>. ?value ?prop ?s; a ?type ").map do |x|
    {
      predicate: x[:prop].value,
      name: iri_to_name(x[:type].value),
      as: iri_to_name(x[:type].value),
      inverse: true
    }
  end
end


# create domain.lisp
puts ";; domain.lisp generated for #{@options[:endpoint]} (graph #{@options[:graph]}) "
classes.each do |klass, c|
  values = {
    name: c[:name],
    klass: klass,
    properties: c[:properties],
    relations: c[:relations] + c[:inverse_relations],
    base_iri: @options[:base],
    plural_name: c[:name] + "s" # todo
  }
  erb = ERB.new(File.read("domain.lisp.erb"))
  puts erb.result(OpenStruct.new(values).instance_eval { binding })
end
