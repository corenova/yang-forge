if /bin\/yfc$/.test require.main.filename
  if process.env.yfc_debug?
    unless console._prefixes?
      (require 'clim') '[forge]', console, true
  else
    console.log = ->

yaml   = require 'js-yaml'
coffee = require 'coffee-script'

path = require 'path'
sys = require 'child_process'
fs = require 'fs'
prettyjson = require 'prettyjson'

class Forge extends (require './compiler')
  @set synth: 'forge', extensions: {}, events: []

  @schema
    name:        @computed (-> return (@access 'module')?.meta 'name'), type: 'string'
    description: @computed (->
      desc = (@access 'module')?.meta 'description'
      desc ?= @meta 'description'
      desc ?= null
      return desc
    ), type: 'string'
    extensions:  @attr 'object'
    modules:     @list Forge, key: 'name', private: true
    features:    @list Object, key: 'name', private: true
    methods:     @list Object, key: 'name', private: true
    events:      @computed (-> return @events ), type: 'array', private: true

  # this is a factory that instantiates based on compiled output of
  # constructor's meta data
  #
  # when called without a 'new' keyword, it creates a forgery of its
  # own class definition representing the blueprint for the new module

  @new: (input={}, hooks={}) ->
    console.assert input instanceof (require 'module'),
      "must pass in 'module' when forging a new module definition, i.e. forge.new(module)"

    # this is a special hack to ensure that while YangForge itself
    # is being constructed/compiled, other dependent modules needed
    # for YangForge construction itself (such as yang-v1-extensions)
    # can properly export themselves.
    if module.id is input.id
      unless module.loaded is true
        if input.parent.parent?
          console.log "[new] searching ancestors for a synthesized forgery..."
          forge = Forge::seek.call input.parent.parent,
            loaded: true
            exports: (v) -> Forge.synthesized v
          if forge?
            console.log "[new] found a forgery!"
            return forge.exports
          if /yang-v1-extensions/.test input.parent.id
            console.log "[new] returning Forge for v1-extensions"
            return Forge

        console.log "[new] forgery initiating SELF-CONSTRUCTION"
        module.exports = Forge

    console.log "[new] processing #{input.id}..."
    try
      pkgdir = (path.dirname input.filename).replace /\/lib$/, ''
      config = input.require (path.resolve pkgdir, './package.json')
      config.pkgdir = pkgdir
      config.origin = input
    catch err
      console.error "[new] unable to discover 'package.json' for the target module"
      throw err

    console.log "forging #{config.name} (#{config.version}) using schema: #{config.schema}"
    return this.call this, config, hooks
  
  oldconstructor: (target, hooks={}) ->
    unless Forge.synthesized @constructor
      console.log "[constructor] creating a new forgery..."
      extensions = @extract 'exports.extension' if Forge.instanceof this
      output = super Forge, ->
        @merge target
        @configure hooks.before
        unless Forge.instanceof target
          @merge extensions
          m = (new this @extract 'extensions').load target.schema
          @mixin m
          @merge m.extract 'exports'
        @configure hooks.after
      console.log "[constructor] forging complete!"
      return output
      
    # instantiate via new
    super
    for method, meta of (@constructor.get 'exports.rpc')
      (@access 'methods').push name: method, meta: meta
    @events = (@constructor.get 'events')
    .map (event) => name: event.key, listener: @on event.key, event.value

  create: (target, data) ->
    return target if target instanceof Forge
    target = @load target unless Forge.instanceof target
    target = Forge target unless Forge.synthesized target
    target = new target data, this
    return target

  report: (options={}) ->
    keys = [ 'name', 'description', 'version', 'license', 'author', 'homepage', 'repository' ]
    if options.verbose
      keys.push 'keywords', 'dependencies', 'optionalDependencies'
    pkg = @constructor.extract.apply @constructor, keys
    pkg.dependencies = Object.keys pkg.dependencies if pkg.dependencies?
    pkg.optionalDependencies = Object.keys pkg.optionalDependencies if pkg.optionalDependencies?

    schema = (@access 'module')?.constructor
    schema ?= @constructor
    schema = do (schema, options) ->
      keys = [
        'name', 'prefix', 'namespace', 'description', 'revision', 'organization', 'contact'
        'include', 'import', 'exports'
      ]
      info = Forge.extract.apply schema, keys
      for k, data of info.include
        info.include[k] = arguments.callee data, options
      for k, data of info.import
        info.import[k] = arguments.callee (data.get 'bindings.module'), options

      info.exports[k] = Object.keys v for k, v of info.exports when v instanceof Object
      if not options.verbose and info.exports.extension? and info.exports.extension.length > 10
        info.exports.extension = info.exports.extension.length
      return info

    res = 
      schema: schema
      package: pkg

    modules = @get 'modules'
    if modules.length > 0
      res.modules = modules.reduce ((a,b) -> a[b.name] = b.description; a), {}
    methods = @get 'methods'
    if methods.length > 0
      res.operations = methods.reduce ((a,b) ->
        a[b.name] = (b.meta?.get 'description') ? '(empty)'; a
      ), {}
    return res

  # RUN THIS FORGE (convenience function for programmatic run)
  @run = (features...) ->
    options = features
      .map (e) -> Forge.Meta.objectify e, on
      .reduce ((a, b) -> Forge.Meta.copy a, b, true), {}
      
    # before we construct, we need to 'normalize' the bindings based on if-feature conditions
    (new this).invoke 'run', options: options
    .catch (e) -> console.error e

  constructor: ->
    @Schema = yaml.Schema.create [
      new yaml.Type '!coffee/function',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) -> coffee.eval data
        predicate: (obj) -> obj instanceof Function
        represent: (obj) -> obj.toString()
      new yaml.Type '!yang/schema',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string' 
        construct: (data) => (@parse schema: data).schema
      new yaml.Type '!yang/module',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) =>
          console.log "processing !yang/module with #{data}"
          try
            source = fs.readFileSync (path.resolve data, 'package.yaml'), 'utf-8'
          catch
            source = data
          @parse source, pkgdir: data
    ]
    super

  parse: (source, options=@options) ->
    @options = options
    source = yaml.load source, schema: @Schema if typeof source is 'string'
    unless source.schema instanceof Object
      try
        source.schema = fs.readFileSync (path.resolve options.pkgdir, source.schema), 'utf-8'
      catch e
        console.log e
        source.schema = fs.readFileSync (path.resolve source.schema), 'utf-8'
      finally
        source.schema = super source.schema
    return source

  preprocess: (source) ->
    source = @parse source if typeof source is 'string'
    source.schema = super source.schema, source
    return source

  compile: (source) ->
    source = @preprocess source if typeof source is 'string'
    source.model = (super source.schema, source)
    return source

module.exports = (new Forge module).compile (fs.readFileSync (path.resolve "package.yaml"), 'utf-8')
