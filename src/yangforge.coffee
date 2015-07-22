if process.env.yfc_debug?
  unless console._prefixes?
    (require 'clim') '[forge]', console, true
else
  console.log = ->

Synth = require 'data-synth'
path = require 'path'
fs = require 'fs'
prettyjson = require 'prettyjson'

class Forge extends Synth
  @set synth: 'forge', extensions: {}, actions: {}

  @extension = (name, func) -> @set "extensions.#{name}.resolver", func
  @action = (name, func) -> @set "actions.#{name}", func
  @feature = (name, func) -> @set "features.#{name}", status: off, hook: func

  toggleFeature = (name, toggle) ->
    feature = @get "features.#{name}"
    if feature?
      feature.status = toggle
      @configure feature.hook, toggle
      console.log "#{@get 'name'} feature #{name} is #{toggle}"
    else
      console.error "#{@get 'name'} does not have feature #{name}"
    
  @enable  = (names...) -> toggleFeature.call this, name, on  for name in names; this
  @disable = (names...) -> toggleFeature.call this, name, off for name in names; this

  @run = ->
    console.info "forgery firing up:\n" + @summary()
    (new this).run()

  @mixin (require './compiler/compiler')

  @summary = ->
    summary =
      (@extract 'name', 'description', 'version', 'schema', 'license', 'author',
      'keywords', 'dependencies', 'features', 'exports')
    summary.dependencies = Object.keys summary.dependencies if summary.dependencies?
    summary.features = Object.keys summary.features if summary.features?
    summary.exports[k] = Object.keys v for k, v of summary.exports when v instanceof Object
    prettyjson.render summary

  # this is a factory that instantiates based on compiled output of
  # constructor's meta data
  #
  # when called without a 'new' keyword, it creates a forgery of its
  # own class definition representing the blueprint for the new module
  constructor: (input={}, hooks={}) ->
    unless Synth.instanceof @constructor
      console.assert input instanceof (require 'module'),
        "must pass in 'module' when forging a new module definition, i.e. forge(module)"

      # this is a special hack to ensure that while YangForge itself
      # is being constructed/compiled, other dependent modules needed
      # for YangForge construction itself (such as yang-v1-extensions)
      # can properly export themselves.
      input.exports = arguments.callee unless input.loaded is true

      console.log "[constructor] processing #{input.id}..."
      try
        pkgdir = (path.dirname input.filename).replace /\/lib$/, ''
        config = input.require (path.resolve pkgdir, './package.json')
        
        # XXX - need to improve ways that schema files are loaded
        schemas =
          (if config.schema instanceof Array then config.schema else [ config.schema ])
          .filter (e) -> e? and !!e
          .map (schema) -> fs.readFileSync (path.resolve pkgdir, schema), 'utf-8'
      catch err
        console.error "[constructor] Unable to discover YANG schema for the target module, missing 'schema' in package.json?"
        throw err

      console.log "forging #{config.name} (#{config.version}) using schema(s): #{config.schema}"
      output = super Forge, ->
        @merge config
        @configure hooks.before
        @merge ((new this @extract 'extensions').compile schema) for schema in schemas
        @configure hooks.after
      console.log "\n" + output?.summary()
      return output

    super

exports = module.exports = Forge module,
  before: ->
    
  after: ->
    #@mixin (require './yangforge-import')
    #@mixin (require './yangforge-export')
    @feature 'cli', (toggle) ->
      if toggle is on
        @mixin (require './features/cli')

    @feature 'restconf', (toggle) ->
      if toggle is on
        @mixin (require './features/restconf')

    # handle RPC calls
    @action 'import', (input) -> @import input
