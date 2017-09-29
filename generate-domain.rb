#!/usr/bin/env ruby

# This is a very ugly, quickly written script
# it generates a domain.lisp file for a provided sparql endpoint and graph

require 'linkeddata'
require 'optparse'
require 'erb'
require 'ostruct'

# options
@options = { endpoint: "https://stad.gent/sparql", graph: "http://stad.gent/dcat/linked-data/", base: "http://stad.gent/dcat/linked-data/" }
OptionParser.new do |opts|
  opts.on("-e", "--endpoint ENDPOINT", "endpoint (required)") do |e|
    @options[:endpoint] = e
  end
  opts.on("-g", "--graph GRAPH", "graph") do |e|
    @options[:endpoint] = e
  end
  opts.on("-b", "--base-iri BASE", "base iri") do |b|
    @options[:base] = b.ends_with?('/') ? b : "#{b}/"
  end
end.parse!


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
      prop: x[:prop].value,
      dtype: type_to_resource_type(x[:dType] ? x[:dType].value : "http://www.w3.org/2001/XMLSchema#string"),
      name: iri_to_name(x[:prop].value)
    }
  end
  c[:relations] =  select("distinct ?prop ?type", "?s a <#{klass}>; ?prop ?value. ?value a ?type  FILTER(isIri(?value))").map do |x|
    {
      prop: x[:prop].value,
      to: x[:type].value,
      name: iri_to_name(x[:prop].value)
    }
  end
  c[:inverse_relations] =  select("distinct ?prop ?type", "?s a <#{klass}>. ?value ?prop ?s; a ?type ").map do |x|
    {
      prop: x[:prop].value,
      from: iri_to_name(x[:type].value),
      name: iri_to_name(x[:prop].value)
    }
  end
end


# create domain.lisp
puts "domain.lisp"
classes.each do |klass, c|
  properties = []
  relations = []
  c[:properties].each do |prop|
    values = {
      name: prop[:name],
      type: prop[:dtype],
      predicate: prop[:prop]
    }              
    properties << values
  end
  c[:relations].each do |rel|
    values = {
      name: rel[:name],
      as: iri_to_name(rel[:prop]),
      predicate: rel[:prop]
    }              
    relations << values
  end
  c[:inverse_relations].each do |rel|
    values = {
      name: rel[:from],
      as: rel[:from],
      predicate: rel[:prop],
      inverse: true
    }              
    relations << values
  end
  values = {
    name: c[:name],
    klass: klass,
    properties: properties,
    relations: relations,
    base_iri: @options[:base],
    plural_name: c[:name] + "s" # todo
  }
  erb = ERB.new(File.read("domain.lisp.erb"))
  puts erb.result(OpenStruct.new(values).instance_eval { binding })
end
