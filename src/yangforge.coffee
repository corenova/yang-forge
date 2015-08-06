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

class Forge extends Synth
  @set synth: 'forge', extensions: {}

  @mixin (require './compiler/compiler')

  @extension = (name, config) -> switch
    when config instanceof Function
      @set "extensions.#{name}.resolver", config
    when config instanceof Object
      @merge "extensions.#{name}", config
    else
      config.warn "attempting to define extension '#{name}' with invalid configuration"
      
  @feature = (name, func) -> @set "features.#{name}", status: off, hook: func
  
  toggleFeature = (name, toggle) ->
    feature = @get "features.#{name}"
    if feature?
      console.log "setting #{@get 'name'} feature #{name} to #{toggle}"
      feature.status = toggle
      @configure feature.hook, toggle
    else
      console.error "#{@get 'name'} does not have feature #{name}"
    
  @enable  = (features...) -> toggleFeature.call this, name, on  for name in features; this
  @disable = (features...) -> toggleFeature.call this, name, off for name in features; this

  @info = (verbose=false) ->
    infokeys = [
      'name', 'description', 'version', 'schema', 'license', 'author', 'homepage',
      'keywords', 'dependencies', 'features', 'exports'
    ]
    if verbose
      infokeys.push 'module', 'optionalDependencies', 'repository', 'bugs'
    info = @extract.apply this, infokeys
    info.dependencies = Object.keys info.dependencies if info.dependencies?
    info.features = Object.keys info.features if info.features?
    info.exports[k] = Object.keys v for k, v of info.exports when v instanceof Object
    if not verbose and info.exports.extension? and info.exports.extension.length > 10
      info.exports.extension = info.exports.extension.length
    for k, v of info.module
      info.module[k] = JSON.stringify v, null, 2
    return info

  @schema
    extensions: @attr 'object'
    modules:    @computed (->
      @access name for name of @get() when name not in [ 'extensions' ]
    ), type: 'array', private: true

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
      # input.exports = arguments.callee unless input.loaded is true
      # console.log "input\n"
      # console.log id: input.id, parent: id: input.parent.id, loaded: input.parent.loaded, grand: id: input.parent.parent?.id, loaded: input.parent.parent?.loaded
      # console.log "module\n"
      # console.log id: module.id, parent: id: module.parent.id, loaded: module.parent.loaded, grand: id: module.parent.parent?.id, loaded: module.parent.parent?.loaded
      if module.id is input.id
        unless module.loaded is true
          console.log "FORGERY NOT YET LOADED..."
          if input.parent.parent?.loaded is true
            # optimization to return the grandparent of the module (which will be an instance of a constructed Forgery)
            grand = input.parent.parent.exports
            return if Forge.synthesized grand then grand else arguments.callee

          console.log "[constructor] forgery initiating SELF-CONSTRUCTION"
          module.exports = arguments.callee
        else
          console.log "FORGERY ALREADY LOADED... (shouldn't be called?)"
          return module.exports

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
      exts = this.get 'exports.extension' if Forge.instanceof this
      output = super Forge, ->
        @merge config
        @merge exports
        @configure hooks.before
        for schema in schemas
          @merge ((new this @extract 'extensions').compile schema, null, exts)
        @configure hooks.after
      console.log "forging complete...."
      console.log output?.info false
      return output
      
    # instantiate via new
    super

  # RUN THIS FORGE
  @run = (config={}) ->
    for feature of @get 'features'
      @enable feature if config[feature] is true

    # before we construct, we need to 'normalize' the bindings based on if-feature conditions
    (new this).run config

  run: (opts) ->
    console.log "forgery firing up..."
    @runners = runners = {}
    for name of (@get 'yangforge.features')
      continue if runners[name]? # already running
      
      feature = @access "yangforge.features.#{name}"
      continue unless feature?

      # need to make this recursive so deeper needs can be met...
      results = for wash in (feature.meta 'needs') or []
        unless runners[wash]?
          console.info "forgery firing up '#{wash}' feature on-behalf of #{name}".green
          runners[wash] = (@access "yangforge.features.#{name}")?.run this
        runners[wash]
      console.log "forgery firing up '#{name}' feature".green
      results.unshift this
      results.push opts
      runners[name] = feature.run.apply feature, results
    @emit 'running', runners

module.exports = Forge.new module,
  before: -> console.log "forgery initiating schema compilations..."
  after: ->
    console.log "forgery AFTER compile event registrations..."
    
    @on 'yangforge:build', (input, output, next) ->
      console.info "should build: #{input.get 'argument'}"
      next()

    @on 'yangforge:build', (input, output, next) ->
      next "this is an example for a failed listener"

    # handle RPC calls

    @on 'yangforge:init', ->
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

    @on 'yangforge:info', (input, output, next) ->
      names = input.get 'argument'
      options = input.get 'options'
      unless names.length
        console.info prettyjson.render (@container.constructor.info options.verbose)
      else
        res = for name in names
          try (require name).info options.verbose
          catch
            try (require( path.resolve name)).info options.verbose
            catch e then console.error "unable to extract info from '#{name}' module\n".red+"#{e}"
        console.info prettyjson.render res
      next()
          
    @on 'yangforge:install', (input, output, next) ->
      packages = input.get 'argument'
      options = input.get 'options'
      for pkg in packages
        console.info "installing #{pkg}" + (if options.save then " --save" else '')
      next()

    @on 'yangforge:list', (input, output, next) ->
      options = input.get 'options'
      modules = (@container.get 'modules').map (e) -> e.constructor.info options.verbose
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
        
    @on 'yangforge:import', (input, output, next) -> @container.import input

    @on 'yangforge:schema', (input, output, next) ->
      options = input.get 'options'
      result = switch
        when options.eval 
          x = @container.compile options.eval
          x?.extract 'module'
        when options.compile
          x = @container.compile (fs.readFileSync options.compile, 'utf-8')
          x?.extract 'module'

      console.assert !!result, "unable to process input"
      result = switch
        when /^json$/i.test options.format then JSON.stringify result, null, 2
        else prettyjson.render result
      console.info result if result?
      next()

    # RUN
    # 1. grabs yangforge constructor and merges other modules into itself
    # 2. disables 'cli' and enables the selected interface
    # 3. run with passed in options
    @on 'yangforge:run', (input, output, next, origin) ->
      names = input.get 'argument'
      options = input.get 'options'
      forgery = @container.constructor
      if options.compile
        try forgery.merge @container.compile (fs.readFileSync options.compile, 'utf-8')
        catch e
          console.error "unable to run native YANG schema file: #{options.compile}\n".red
          throw e
      else
        slaves = for name in names
          try require name
          catch then require (path.resolve name)
        forgery.mixin slave for slave in slaves
      while arg = process.argv.shift()
        break if arg is '--'
      forgery.disable('cli').run options

    #@mixin (require './yangforge-import')
    #@mixin (require './yangforge-export')
    @feature 'cli', (toggle) -> switch toggle
      when on then @bind 'yangforge.features.cli', (require './features/cli')
      else @unbind 'yangforge.features.cli'

    @feature 'express', (toggle) -> switch toggle
      when on then @bind 'yangforge.features.express', (require './features/express')
      else @unbind 'yangforge.features.express'
        
    @feature 'restjson', (toggle) -> switch toggle
      when on
        # hard-coded for now...
        @enable 'express'
        @bind 'yangforge.features.restjson', (require './features/restjson')
      else @unbind 'yangforge.features.restjson'

    @feature 'debug', (toggle) ->

