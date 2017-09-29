#!/usr/bin/env ruby

# This is a very ugly, quickly written script
# it generates a domain.lisp file for a provided sparql endpoint and graph

require 'linkeddata'
require 'optparse'
require 'yaml'

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

def template_replace(template, map)
  map.each do |key, value|
    template = template.gsub("{{#{key}}}",value)
  end
  template
end

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
puts classes.to_yaml

resource_template = <<EOF 
(define-resource {{name}} ()
   :class (s-url "{{class}}")
   :properties `({{properties}}
                )
   :has-many `({{relations}}
              )
   :resource-base(s-url "{{base_iri}}")
   :on-path "{{plural_name}}"
)
EOF

property_template = <<EOF 
({{name}} :{{type}} , (s-url "{{predicate}}"))
EOF

relation_template = <<EOF 
({{name}} :via ,(s-url "{{predicate}}")
\t\t\t:as "{{name}}"
\t\t)
EOF

inverse_relation_template = <<EOF 
({{from}} :via ,(s-url "{{predicate}}")
\t\t\t:inverse t
\t\t\t:as "{{from}}"
\t\t)
EOF

puts ""
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
    properties << template_replace(property_template, values)
  end
  c[:relations].each do |rel|
    values = {
      name: rel[:name],
      to: rel[:to],
      predicate: rel[:prop]
    }              
    relations << template_replace(relation_template, values)
  end
  c[:inverse_relations].each do |rel|
    values = {
      from: rel[:from],
      predicate: rel[:prop]
    }              
    relations << template_replace(inverse_relation_template, values)
  end
  values = {
    name: c[:name],
    class: klass,
    properties: properties.join("\t\t"),
    relations: relations.join("\t\t"),
    base_iri: @options[:base],
    plural_name: c[:name] + "s" # todo
  }
  puts template_replace(resource_template, values)
end
