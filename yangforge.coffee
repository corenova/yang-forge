# BELOW is a bit HACKISH
if /bin\/yfc$/.test require?.main?.filename
  if process.env.yfc_debug?
    unless console._prefixes?
      (require 'clim') '[forge]', console, true
  else
    console.log = ->

promise = require 'promise'
synth   = require 'data-synth'
yaml    = require 'js-yaml'
coffee  = require 'coffee-script'
path    = require 'path'
fs      = require 'fs'
url     = require 'url'
needle  = require 'needle'

prettyjson = require 'prettyjson'
Compiler   = require './yang-compiler'

class Forge extends Compiler
  Promise: promise
  Synth: synth
  
  # NOT the most efficient way to do it...
  genSchema: (options={}) ->
    readFile = (data, opts) ->
      try
        try
          pkgdir = path.dirname (path.resolve opts.pkgdir, data)
          data = fs.readFileSync (path.resolve opts.pkgdir, data), 'utf-8'
        catch
          pkgdir = path.dirname (path.resolve data)
          data = fs.readFileSync (path.resolve data), 'utf-8'
      catch
      return data: data, pkgdir: pkgdir
    
    yaml.Schema.create [
      new yaml.Type '!coffee/function',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) -> coffee.eval data
        predicate: (obj) -> obj instanceof Function
        represent: (obj) -> obj.toString()
      new yaml.Type '!yang',
        kind: 'mapping'
        resolve:   (data={}) ->
          # preprocessing should also validate if context available
          #@preprocess data
          typeof data.module is 'object'
        construct: (data) -> data
      new yaml.Type '!yang/extension',
        kind: 'mapping'
        resolve:   (data={}) -> true
        construct: (data) -> data
      new yaml.Type '!yang/schema',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string' 
        construct: (data) =>
          console.log "processing !yang/schema using: #{data}"
          res = readFile data, options
          (@parse schema: res.data, options).schema
      new yaml.Type '!yaml/schema',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) =>
          console.log "processing !yaml/schema using: #{data}"
          res = readFile data, options
          @parse res.data, pkgdir: res.pkgdir
    ]

  parse: (source, opts={}) ->
    source = yaml.load source, schema: @genSchema opts if typeof source is 'string'
    unless source?.schema instanceof Object
      source.schema = super source.schema if source.schema?
    return source

  preprocess: (source, opts) ->
    source = @parse source, opts if typeof source is 'string'
    source.parent = @source
    source.schema = super source.schema, source if source.schema?
    delete source.parent
    return source

  compile: (source, opts={}) ->
    source = @preprocess source, opts
    model = super source.schema, source if source.schema?
    return switch
      when model? then ((synth.Meta source).bind model).configure opts.hook
      else source

  load: (source, opts) ->
    source = @compile source, opts unless synth.instanceof source
    return switch
      when (synth.instanceof source) then new source
      else source

  # performs async import of a target source path, accepts 'source' as array
  import: (source, opts={}, resolve, reject) ->
    if source instanceof Array
      return @Promise.all (@import x, opts for x in source)
    unless resolve? and reject?
      return @invoke arguments.callee, source, opts 
    
    url = url.parse source if typeof source is 'string'
    switch url.protocol
      when 'http:','https:'
        needle.get source, (err, res) =>
          if not err and res.statusCode is 200 then resolve @load res.body else reject err
      when 'github:'
        needle.get "https://raw.githubusercontent.com/#{url.hostname}#{url.pathname}", (err, res) =>
          if not err and res.statusCode is 200 then resolve @load res.body else reject err
      else
        fs.readFile (path.resolve url.pathname), 'utf8', (err, data) =>
          if err? then return reject err
          resolve @load data, pkgdir: (path.dirname (path.resolve url.pathname))
        
  render: prettyjson.render

  info: (about, options={}) ->
    schema = about.constructor
    schema = do (schema, options) ->
      keys = [
        'name', 'prefix', 'namespace', 'description', 'revision', 'organization', 'contact'
        'include', 'import'
      ]
      info = synth.extract.apply schema, keys
      return info

    summarize = (what) ->
      (synth.objectify k, v.description for k, v of what)
      .reduce ((a,b) -> synth.copy a, b), {}

    info = synth.extract.call about.parent.constructor, 'name', 'description', 'license', 'keywords'
    info.schema     = schema
    info.typedefs   = summarize about.meta 'typedef'
    info.features   = summarize about.meta 'feature'
    info.operations = summarize about.meta 'rpc'
    return info

  # RUN THIS FORGE (convenience function for programmatic run)
  run: (features...) ->
    options = features
      .map (e) -> synth.objectify e, on
      .reduce ((a, b) -> synth.copy a, b, true), {}
      
    (@access 'yangforge').invoke 'run', options: options
    .catch (e) -> console.error e

  valueOf:  -> @source
  toString: -> 'Forge'

#
# self-forge using the yangforge.yaml schema
# 
module.exports = (new Forge).load '!yaml/schema yangforge.yaml',
  pkgdir: __dirname
  hook: ->
    @mixin Forge
    @include source: @extract()

