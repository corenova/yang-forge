Synth = require 'data-synth'

class Forge extends Synth
  @set synth: 'forge', extensions: {}, actions: {}

  @extension = (name, func) -> @set "extensions.#{name}.resolver", func
  @action = (name, func) -> @set "actions.#{name}", func

  @mixin (require 'yang-compiler')

  assert = require 'assert'
  path = require 'path'
  fs = require 'fs'

  # this is a factory that instantiates based on compiled output of
  # constructor's meta data
  #
  # when called without a 'new' keyword, it creates a forgery of its
  # own class definition representing the blueprint for the new module
  constructor: (input={}, hooks={}) ->
    unless Synth.instanceof @constructor
      assert input instanceof (require 'module'),
        "must pass in 'module' when forging a new module definition, i.e. forge(module)"

      # this is a special hack to ensure that while YangForge itself
      # is being constructed/compiled, other dependent modules needed
      # for YangForge construction itself (such as yang-v1-extensions)
      # can properly export themselves.
      module.exports = arguments.callee unless module.loaded is true

      console.log "INFO: [forge] processing #{input.id}..."
      try
        pkgdir = path.dirname input.filename
        config = require (path.resolve pkgdir, './package.json')
        schemas =
          (if config.schema instanceof Array then config.schema else [ config.schema ])
          .filter (e) -> e? and !!e
          .map (schema) -> fs.readFileSync (path.resolve pkgdir, schema), 'utf-8'
      catch err
        console.log "Unable to discover YANG schema for the target module, missing 'schema' in package.json?"
        throw err

      console.log "INFO: [forge] forging #{config.name} (#{config.version}) using schema(s): #{config.schema}"

      return super Forge, ->
        @merge config
        @configure hooks.before
        @merge ((new this @extract 'extensions').compile schema) for schema in schemas
        @configure hooks.after

    super

module.exports = Forge module,
  before: ->
    
  after: ->
    #@mixin (require './yangforge-import')
    #@mixin (require './yangforge-export')
    @action 'import', (input) -> @import input
