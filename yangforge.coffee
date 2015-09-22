if /bin\/yfc$/.test require.main.filename
  if process.env.yfc_debug?
    unless console._prefixes?
      (require 'clim') '[forge]', console, true
  else
    console.log = ->

synth  = require 'data-synth'
yaml   = require 'js-yaml'
coffee = require 'coffee-script'
path   = require 'path'
fs     = require 'fs'

prettyjson = require 'prettyjson'

class Forge extends (require './yang-compiler')

  Synth: synth
  constructor: (@options={}) ->
    @SCHEMA = SCHEMA = yaml.Schema.create [
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
      new yaml.Type '!yang/schema',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string' 
        construct: (data) => (@parse schema: data).schema
      new yaml.Type '!yang/extension',
        kind: 'mapping'
        resolve:   (data={}) -> true
        construct: (data) -> data
      new yaml.Type '!yaml/schema',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) =>
          console.log "processing !yaml/schema using: #{data}"
          try
            try
              pkgdir = path.dirname (path.resolve @options.pkgdir, data)
              data = fs.readFileSync (path.resolve @options.pkgdir, data), 'utf-8'
            catch
              pkgdir = path.dirname (path.resolve data)
              data = fs.readFileSync (path.resolve data), 'utf-8'
          catch
          @parse data, pkgdir: pkgdir
    ]
    unless @options.fork is true
      # self-compile primary source...
      @options.pkgdir = __dirname
      data = (fs.readFileSync (path.resolve __dirname, "yangforge.yaml"), 'utf-8')
      return @load data, null, ->
        @mixin Forge
        @include SCHEMA: SCHEMA, source: @extract()
    super

  valueOf:  -> @constructor.extract()
  toString: -> 'Forge'

  parse: (source, options=@options) ->
    @options = options # XXX - be careful with this one...
    source = yaml.load source, schema: @SCHEMA if typeof source is 'string'
    unless source?.schema instanceof Object
      try
        try
          source.schema = fs.readFileSync (path.resolve options.pkgdir, source.schema), 'utf-8'
        catch
          source.schema = fs.readFileSync (path.resolve source.schema), 'utf-8'
      catch
      source.schema = super source.schema if source.schema?
    return source

  preprocess: (source) ->
    source = @parse source if typeof source is 'string'
    source.parent = @source
    source.schema = super source.schema, source if source.schema?
    delete source.parent
    return source

  compile: (source) ->
    source = @preprocess source
    model = super source.schema, source if source.schema?
    return switch
      when model? then (synth.Meta source).bind model
      else source

  load: (source, data, hook) ->
    source = @compile source unless synth.instanceof source
    return switch
      when (synth.instanceof source) then new (source.configure hook) data, this
      else source

  render: prettyjson.render

  # RUN THIS FORGE (convenience function for programmatic run)
  run: (features...) ->
    options = features
      .map (e) -> synth.objectify e, on
      .reduce ((a, b) -> synth.copy a, b, true), {}
      
    (@access 'yangforge').invoke 'run', options: options
    .catch (e) -> console.error e

exports = module.exports = new Forge strict: true
exports.Forge = Forge
