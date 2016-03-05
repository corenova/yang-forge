yaml   = require 'js-yaml'
url    = require 'url'
coffee = require 'coffee-script'

module.exports = yaml.Schema.create [

  # contains and links
  new yaml.Type '!npm',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> url.parse "npm:?#{data}"

  new yaml.Type '!core',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> url.parse "core:?#{data}"

  new yaml.Type '!feature',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> url.parse "feature:?#{data}"

  new yaml.Type '!magnet',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> url.parse "magnet:?#{data}"

  # provides types (local files only)
  new yaml.Type '!spec',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> url.parse "file:#{data}"

  new yaml.Type '!schema',
    kind: 'scalar'
    resolve:   (data) -> typeof data is 'string'
    construct: (data) -> url.parse "file:#{data}"

  # transforms types
  new yaml.Type '!xform',
    kind: 'mapping'
    resolve:   (data={}) -> true
    construct: (data) -> data

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

]
