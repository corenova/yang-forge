yaml = require 'js-yaml'
url  = require 'url'

module.exports = yaml.Schema.create [

  # contains types
  new yaml.Type '!npm',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) ->
      console.log "processing !npm using: #{data}"

      require (path.resolve options.pkgdir, data)

  new yaml.Type '!require',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) ->
      console.log "processing !require using: #{data}"
      require (path.resolve options.pkgdir, data)
  new yaml.Type '!coffee',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> coffee.eval? data
  new yaml.Type '!coffee/function',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> coffee.eval? data
    predicate: (obj) -> obj instanceof Function
    represent: (obj) -> obj.toString()
  new yaml.Type '!json',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) =>
      console.log "processing !json using: #{data}"
      [ data, pkgdir ] = fetch data, options
      @parse data, format: 'json'
  new yaml.Type '!yang',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) =>
      console.log "processing !yang using: #{data}"
      [ data, pkgdir ] = fetch data, options
      options.pkgdir ?= pkgdir if pkgdir?
      @parse data, format: 'yang', options
  new yaml.Type '!xform',
    kind: 'mapping'
    resolve:   (data={}) -> true
    construct: (data) -> data
]
