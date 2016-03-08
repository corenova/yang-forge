yaml   = require 'js-yaml'
url    = require 'url'
coffee = require 'coffee-script'

keywords = [
  'npm', 'core', 'feature', 'machine', 'magnet'
]

extensions = keywords.map (x) -> new yaml.Type "!#{x}",
  kind: 'scalar'
  resolve:   (data) -> typeof data is 'string'
  construct: (data) -> url.parse "#{x}:?#{data}"

module.exports = yaml.Schema.create extensions.concat [

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
