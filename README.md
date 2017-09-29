# domain.lisp generator
A script to generate a domain.lisp based on existing data.

```
./generate-domain.rb
Usage: generate-domain [options]
    -b, --base-iri BASE              base iri (required)
    -e, --endpoint ENDPOINT          endpoint (required)
    -g, --graph GRAPH                graph
    -h, --help                       help
```

Example
```
./generate-domain.rb -b http://example.com/catalog/ -e https://stad.gent/sparql -g http://stad.gent/dcat/linked-data/ > domain.lisp
```