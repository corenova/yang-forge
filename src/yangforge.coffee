if process.env.yfc_debug?
  unless console._prefixes?
    (require 'clim') '[forge]', console, true
else
  console.log = ->

Synth = require 'data-synth'
path = require 'path'
sys = require 'child_process'
fs = require 'fs'
prettyjson = require 'prettyjson'
Promise = require 'promise'

class Forge extends Synth
  @set synth: 'forge', extensions: {}, events: []

  @mixin (require './compiler/compiler')

  @extension = (name, config) -> switch
    when config instanceof Function
      @set "extensions.#{name}.resolver", config
    when config instanceof Object
      @merge "extensions.#{name}", config
    else
      config.warn "attempting to define extension '#{name}' with invalid configuration"

  @on = (event, func) ->
    [ target, action ] = event.split ':'
    unless action?
      @merge events: [ key: target, value: func ]
    else
      (@get "bindings.#{target}")?.merge 'events', [ key: action, value: func ]

  @info = (verbose=false) ->
    infokeys = [
      'name', 'description', 'version', 'schema', 'license', 'author', 'homepage',
      'keywords', 'dependencies', 'exports'
    ]
    if verbose
      infokeys.push 'module', 'optionalDependencies', 'repository', 'bugs'
    info = @extract.apply this, infokeys
    info.schema = (@get "bindings.#{@get "bindings.name"}")?.info verbose
    info.dependencies = Object.keys info.dependencies if info.dependencies?
    info.exports[k] = Object.keys v for k, v of info.exports when v instanceof Object
    if not verbose and info.exports.extension? and info.exports.extension.length > 10
      info.exports.extension = info.exports.extension.length
    for k, v of info.module
      info.module[k] = JSON.stringify v, null, 2
    return info

  @schema
    extensions: @attr 'object'
    events:     @computed (-> return @events ), type: 'array', private: true
    features:   @list Forge.Interface, key: 'name', private: true
    modules:    @list Forge.Meta, key: 'name', private: true
    methods:    @computed (-> return Object.keys(@meta 'exports.rpc') ), type: 'array', private: true

  # this is a factory that instantiates based on compiled output of
  # constructor's meta data
  #
  # when called without a 'new' keyword, it creates a forgery of its
  # own class definition representing the blueprint for the new module

  @new: -> this.apply this, arguments
  
  constructor: (input={}, hooks={}) ->
    unless Forge.synthesized @constructor
      console.assert input instanceof (require 'module'),
        "must pass in 'module' when forging a new module definition, i.e. forge.new(module)"

      # this is a special hack to ensure that while YangForge itself
      # is being constructed/compiled, other dependent modules needed
      # for YangForge construction itself (such as yang-v1-extensions)
      # can properly export themselves.
      if module.id is input.id
        unless module.loaded is true
          if input.parent.parent?.loaded is true
            console.log "[constructor] searching ancestors for a synthesized forgery..."
            forge = Forge::seek?.call input.parent.parent,
              loaded: true
              exports: (v) -> Forge.synthesized v
            if forge?
              console.log "[constructor] found a forgery!"
            return forge?.exports ? arguments.callee
          
          console.log "[constructor] forgery initiating SELF-CONSTRUCTION"
          module.exports = arguments.callee
        else
          console.log "FORGERY ALREADY LOADED... (shouldn't be called?)"
          return module.exports

      console.log "[constructor] processing #{input.id}..."
      try
        pkgdir = (path.dirname input.filename).replace /\/lib$/, ''
        config = input.require (path.resolve pkgdir, './package.json')
        config.pkgdir = pkgdir
        config.origin = input
        schema = fs.readFileSync (path.resolve pkgdir, config.schema), 'utf-8'
      catch err
        console.error "[constructor] Unable to discover YANG schema for the target module, missing 'schema' in package.json?"
        throw err

      console.log "forging #{config.name} (#{config.version}) using schema: #{config.schema}"
      exts = this.get 'exports.extension' if Forge.instanceof this
      output = super Forge, ->
        @merge config
        @configure hooks.before
        @merge ((new this @extract 'extensions').compile schema, null, exts)
        @configure hooks.after
      console.log "forging complete...."
      console.log output?.info false
      return output
      
    # instantiate via new
    super
    @events = (@constructor.get 'events')
    .map (event) => name: event.key, listener: @on event.key, event.value

  # RUN THIS FORGE (convenience function for programmatic run)
  @run = (features...) ->
    options = features
      .map (e) -> Forge.Meta.objectify e, on
      .reduce ((a, b) -> Forge.Meta.copy a, b, true), {}
      
    # before we construct, we need to 'normalize' the bindings based on if-feature conditions
    (new this).invoke 'run', input: options: options

  invoke: (event, data, scope=this) ->
    unless event?
      return Promise.reject "cannot invoke without specifying action"
      
    listeners = @listeners event
    console.log "invoking '#{event}' for handling by #{listeners.length} listeners"

    rpc = @meta "exports.rpc.#{event}"
    action = new rpc data
    promises =
      for listener in listeners
        do (listener) ->
          new Promise (resolve, reject) ->
            listener.apply scope, [
              (action.access 'input')
              (action.access 'output')
              (err) -> if err? then reject err else resolve action
            ]
    unless promises.length > 0
      promises.push Promise.reject "missing listeners for '#{event}' event"

    return Promise.all promises
      .then (res) ->
        console.log "promise all returned with"
        console.log res
        for item in res
          console.log "got back #{item} from listener"
        return action

module.exports = Forge.new module,
  before: -> console.log "forgery initiating schema compilations..."
  after: ->
    console.log "forgery invoking after hook..."

    # update yangforge.runtime bindings
    @rebind 'yangforge.runtime.features', (prev) =>
      @computed (-> (@seek synth: 'forge').get 'features' ), type: 'array'

    @rebind 'yangforge.runtime.modules', (prev) =>
      @computed (-> (@seek synth: 'forge').get 'modules' ), type: 'array'

    @on 'build', (input, output, next) ->
      console.info "should build: #{input.get 'arguments'}"
      next()

    @on 'build', (input, output, next) ->
      next "this is an example for a failed listener"

    @on 'init', ->
      console.info "initializing yangforge environment...".grey
      child = sys.spawn 'npm', [ 'init' ], stdio: 'inherit'
      # child.stdout.on 'data', (data) ->
      #   console.info (data.toString 'utf8').replace 'npm', 'yfc'
      child.on 'close', process.exit.bind process
      child.on 'error', (err) ->
        switch err.code
          when 'ENOENT' then console.error "npm does not exist, try --help".red
          when 'EACCES' then console.error "npm not executable. try chmod or run as root".red
        process.exit 1

    @on 'info', (input, output, next) ->
      names = input.get 'arguments'
      options = input.get 'options'
      unless names.length
        console.info prettyjson.render (@constructor.info options.verbose)
      else
        res = for name in names
          try (@load name).info options.verbose
          catch e then console.error "unable to extract info from '#{name}' module\n".red+"#{e}"
        console.info prettyjson.render res
      next()

    @on 'install', (input, output, next) ->
      packages = input.get 'arguments'
      options = input.get 'options'
      for pkg in packages
        console.info "installing #{pkg}" + (if options.save then " --save" else '')
      next()

    @on 'list', (input, output, next) ->
      options = input.get 'options'
      modules = (@get 'modules').map (e) -> e.constructor.info options.verbose
      unless options.verbose
        console.info prettyjson.render modules
        return next()
      child = sys.exec 'npm list --json', timeout: 5000
      child.stdout.on 'data', (data) ->
        result = JSON.parse data
        results = for mod in modules when result.name is mod.name
          Synth.copy mod, result
        console.info prettyjson.render results
      child.stderr.on 'data', (data) -> console.warn data.red
      child.on 'close', (code) -> next()

    @on 'import', (input, output, next) -> @import input

    @on 'schema', (input, output, next) ->
      options = input.get 'options'
      result = switch
        when options.eval 
          x = @compile options.eval
          x?.extract 'module'
        when options.compile
          x = @compile (fs.readFileSync options.compile, 'utf-8')
          x?.extract 'module'

      console.assert !!result, "unable to process input"
      result = switch
        when /^json$/i.test options.format then JSON.stringify result, null, 2
        else prettyjson.render result
      console.info result if result?
      next()

    @on 'run', (input, output, next) ->
      targets = input.get 'arguments'
      features = input.get 'options'

      console.log "forgery run with #{targets}..."
      console.log features

      if features.cli is true
        features = cli: on
      else
        @set 'features.cli', off
        process.argv = [] # hack for now...
      
      for target in targets
        try (@access 'modules').push new (@load target) null, this
        catch e then console.warn "unable to load target '#{target}' due to #{e}"

      for feature, arg of features
        continue unless arg? and arg
        try (@access 'features').push new (@load "features/#{feature}") null, this
        catch e then console.warn "unable to load feature '#{feature}' due to #{e}"

      # run passed in features
      console.log "forgery firing up..."
      for feature in @get 'features' when feature instanceof Forge.Meta
        do (feature) =>
          name = feature.meta 'name'
          deps = for dep in (feature.meta 'needs') or []
            console.log "forgery firing up '#{dep}' feature on-behalf of #{name}".green
            (@get "features.#{dep}")?.run this, features[dep]
          needs = deps.length
          deps.unshift this
          deps.push features[name]
          console.log "forgery firing up '#{name}' feature with #{needs} dependents".green
          feature.run.apply feature, deps

      # console.log "forgery fired up!"
      # console.warn @get 'features'
      # console.warn @get 'modules'
      next()
      
    @on 'enable', (input, output, next) ->
      for key in input.get 'features'
        (@resolve 'feature', key)?.enable()
      next()
