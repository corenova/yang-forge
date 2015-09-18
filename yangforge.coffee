if /bin\/yfc$/.test require.main.filename
  if process.env.yfc_debug?
    unless console._prefixes?
      (require 'clim') '[forge]', console, true
  else
    console.log = ->

yaml   = require 'js-yaml'
coffee = require 'coffee-script'
path   = require 'path'
fs     = require 'fs'

class Forge extends (require './yang-compiler')
  
  constructor: (@options={}) ->
    forge = this
    @Synth = require 'data-synth'
    @Schema = yaml.Schema.create [
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
        construct: (data) -> (forge.parse schema: data).schema
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
              pkgdir = path.dirname (path.resolve options.pkgdir, data)
              data = fs.readFileSync (path.resolve options.pkgdir, data), 'utf-8'
            catch
              pkgdir = path.dirname (path.resolve data)
              data = fs.readFileSync (path.resolve data), 'utf-8'
          catch
          forge.parse data, pkgdir: pkgdir
    ]
    unless @options.fork is true
      # self-compile primary source...
      @options.pkgdir = __dirname
      @source = @compile (fs.readFileSync (path.resolve __dirname, "yangforge.yaml"), 'utf-8')
      @source.valueOf = -> 'yangforge'
      @forge = @source.model.yangforge
    super

  valueOf:  -> @source
  toString: -> 'Forge'

  parse: (source, options=@options) ->
    @options = options # XXX - be careful with this one...
    source = yaml.load source, schema: @Schema if typeof source is 'string'
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
    source.model = super source.schema, source if source.schema?
    return source

  load: -> @compile arguments...

  # RUN THIS FORGE (convenience function for programmatic run)
  run: (features...) ->
    options = features
      .map (e) => @Synth.Meta.objectify e, on
      .reduce ((a, b) => @Synth.Meta.copy a, b, true), {}
      
    # before we construct, we need to 'normalize' the bindings based
    # on if-feature conditions
    @forge.invoke 'run', options: options
    .catch (e) -> console.error e

module.exports = new Forge strict: true
