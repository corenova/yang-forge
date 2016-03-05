# core - the embodiment of the soul of the application

yang     = require 'yang-js'
yaml     = require 'js-yaml'
events   = require 'events'
traverse = require 'traverse'
tosource = require 'tosource'
# sys =      require 'child_process'
# treeify =  require 'treeify'
# js2xml =   require 'js2xmlparser'

class Core extends yang.Module
  @set synth: 'core'
  @mixin events.EventEmitter

  @toSource: (opts={}) ->
    source = @extract()
    delete source.bindings

    self = this
    source = (traverse source).map (x) ->
      if self.instanceof x
        obj = x.extract 'overrides'
        self.copy obj, x.get 'bindings'
        @update obj
        @after (y) ->
          for k, v of y when k isnt 'overrides'
            unless v?
              delete y[k]
              continue
            # TODO: checking for b to be Array is hackish
            for a, b of v when b instanceof Array
              y.overrides ?= {}
              y.overrides["#{k}.#{a}"] = b
          @update y.overrides, true

    source = switch opts.format
      when 'yaml' then yaml.dump source, lineWidth: -1
      when 'json'
        opts.space ?= 2
        source = (traverse source).map (x) ->
          if x instanceof Function
            @update self.objectify '!js/function', tosource x
        JSON.stringify source, null, opts.space
      when 'tree' then treeify.asTree source, true
      else
        source
    switch opts.encoding
      when 'base64' then (new Buffer source).toString 'base64'
      else source

  attach: -> super; @emit 'attach', arguments...

  toString: -> "Core:#{@meta 'name'}"

  render: (data=this, opts={}) ->
    return data.toSource opts if Runtime.instanceof data

    switch opts.format
      when 'json' then JSON.stringify data, null, opts.space
      when 'yaml'
        ((require 'prettyjson').render? data, opts) ? (yaml.dump data, lineWidth: -1)
      when 'tree' then treeify.asTree data, true
      when 'xml' then js2xml 'schema', data, prettyPrinting: indentString: '  '
      else data

  info: (options={}) ->
    summarize = (what) ->
      (synth.objectify k, (v?.description ? null) for k, v of what)
      .reduce ((a,b) -> synth.copy a, b), {}

    info = @constructor.extract 'name', 'description', 'license', 'keywords'
    for name, schema of @constructor.get 'schema.module'
      info.schema = do (schema, options) ->
        keys = [
          'name', 'prefix', 'namespace', 'description', 'revision', 'organization', 'contact'
          'include', 'import'
        ]
        meta = synth.extract.apply schema, keys
        return meta
      info.features   = summarize schema.feature if schema.feature?
      info.typedefs   = summarize schema.typedef if schema.typedef?
      info.operations = summarize schema.rpc     if schema.rpc?
      break; # just return ONE...

    return @render info, options

  enable: (name, options) ->
    @feature[name] ?= (@meta "feature.#{name}")?.construct? options

  disable: (name) ->
    @feature[name]?.destroy?()
    delete @feature[name]

  run: (features...) ->
    if 'cli' in features
      (@resolve 'feature', 'cli').run this
      return

    options = features
      .map (e) ->
        unless typeof e is 'object'
          synth.objectify e, on
        else e
      .reduce ((a, b) -> synth.copy a, b, true), {}

    (@access 'yangforge').invoke 'run', options: options
    .catch (e) -> console.error e

exports = module.exports = Core
exports.Schema = require './core-schema'
exports.load = (input, opts={}) ->
  opts.schema ?= @Schema
  if typeof input is 'string' then yaml.load input, opts
  else input

# console = (require 'clim') '[forge]'
# unless process.stderr?
#   process.stderr = write: ->
# if process.env.yfc_debug?
#   console.debug = console.log
# else
#   console.log = ->


  # TBD
  # export: (input=this) ->
  #   console.assert input instanceof Object, "invalid input to export module"
  #   console.assert typeof input.name is 'string' and !!input.name,
  #     "need to pass in 'name' of the module to export"
  #   format = input.format ? 'json'
  #   m = switch
  #     when (synth.instanceof input) then input
  #     else @resolve 'module', input.name
  #   console.assert (synth.instanceof m),
  #     "unable to retrieve requested module #{input.name} for export"

  #   obj = m.extract 'name', 'schema', 'map', 'extensions', 'importers', 'exporters', 'procedures'
  #   for key in [ 'extensions', 'importers', 'procedures' ]
  #     obj[key]?.toJSON = ->
  #       @[k] = tosource v for k, v of this when k isnt 'toJSON' and v instanceof Function
  #       this

  #   return switch format
  #     when 'json' then JSON.stringify obj
