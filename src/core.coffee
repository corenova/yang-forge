# core - the embodiment of the soul of the application
console.debug ?= console.log if process.env.yang_debug?

yang     = require 'yang-js'
yaml     = require 'js-yaml'
events   = require 'events'
assert   = require 'assert'

class Core extends yang.Module
  @set synth: 'core'
  @mixin events.EventEmitter

  constructor: (data, @engine) -> super

  enable: (feature, data, args...) ->
    Feature = (@meta 'maker').resolve 'feature', feature
    assert Feature instanceof Function,
      "cannot enable incompatible feature"

    @once 'start', (engine) =>
      console.debug? "[Core:enable] starting with '#{feature}'"
      (new Feature data, this).invoke 'main', args...
      .then (res) -> console.log res
      .catch (err) -> console.error err

  attach: -> super; @emit 'attach', arguments...

  toString: -> "Core:#{@meta 'name'}"

  run: -> @invoke 'main', arguments...


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

exports = module.exports = Core
exports.load = (input, opts={}) ->
  opts.schema ?= require './schema'
  if typeof input is 'string' then yaml.load input, opts
  else input
