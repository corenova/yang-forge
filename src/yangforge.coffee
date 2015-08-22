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

  @schema
    extensions: @attr 'object'
    modules:    @list Forge, key: 'name', private: true
    features:   @list Forge.Interface, key: 'name', private: true
    methods:    @list Object, key: 'name', private: true
    events:     @computed (-> return @events ), type: 'array', private: true

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
          return forge?.exports ? Forge

        console.log "[new] forgery initiating SELF-CONSTRUCTION"
        module.exports = Forge
      else
        console.log "FORGERY ALREADY LOADED... (shouldn't be called?)"
        return module.exports

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
  
  constructor: (target, hooks={}) ->
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
    keys = [ 'name', 'description', 'version', 'license', 'author', 'homepage', 'repository', 'exports' ]
    if options.verbose
      keys.push 'keywords', 'dependencies', 'optionalDependencies'
    pkg = @constructor.extract.apply @constructor, keys
    pkg.dependencies = Object.keys pkg.dependencies if pkg.dependencies?
    pkg.optionalDependencies = Object.keys pkg.optionalDependencies if pkg.optionalDependencies?

    pkg.exports[k] = Object.keys v for k, v of pkg.exports when v instanceof Object
    if not options.verbose and pkg.exports.extension? and pkg.exports.extension.length > 10
      pkg.exports.extension = pkg.exports.extension.length

    name = @get 'name'
    name ?= pkg.name
    schema = (@access name)?.constructor
    schema ?= @constructor
    schema = do (schema, options) ->
      keys = [
        'prefix', 'namespace', 'description', 'revision', 'organization', 'contact'
        'include', 'import'
      ]
      info = Forge.extract.apply schema, keys
      for k, data of info.include
        info.include[k] = arguments.callee data, options
      for k, data of info.import
        info.import[k] = data?.get? 'name'
      return info

    res = 
      name: name
      schema: schema
      package: pkg

    modules = @get 'modules'
    if modules.length > 0
      res.modules = modules.reduce ((a,b) =>
        m = @access "modules.#{b.name}"
        unless m.meta 'description'
          m = m.access b.name
        a[b.name] = (m.meta 'description') ? '(empty)'; a
      ), {}
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

  invoke: (rpc, data) ->
    method = @access "methods.#{rpc}"
    unless method?
      return Promise.reject "cannot invoke without available '#{rpc}' operation"
    schema = new method.meta input: data
    super method.name, (schema.access 'input'), (schema.access 'output'), (e) -> throw e if e?; true
      .then (res) -> return schema.access 'output'

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
      targets = input.get 'arguments'
      targets.push this unless targets.length > 0
      results = for target in targets
        try (@create target).report input.get 'options'
        catch e then console.error "unable to extract info from '#{target}' module\n".red+"#{e}"
      output?.set 'result', results

      # below should be called only if cli interface...
      console.info prettyjson.render results
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

    @on 'infuse', (input, output, next) ->
      modules = for target in input.get 'targets'
        console.log "<infuse> absorbing a new source '#{target.source}' into running forge"
        target = @create target.source, target.data
        (@access 'modules').push target if target?
        target
      output.set 'message', 'request processed successfully'
      output.set 'modules', modules
      console.log "<infuse> completed"
      next()

    @on 'defuse', (input, output, next) ->
      (@access 'modules').remove input.get 'names'
      output.set 'message', 'OK'
      next()

    @on 'run', (input, output, next) ->
      @invoke 'infuse', targets: (input.get 'arguments').map (e) -> source: e
      .catch (e) -> next e
      .then (result) =>
        modules = result.get 'modules'
        console.log "<run> starting up: " + modules.map (e) -> e.name
        
        features = input.get 'options'
        if features.cli is true
          features = cli: on
        else
          @set 'features.cli', off
          process.argv = [] # hack for now...

        console.log "forgery firing up #{Object.keys(features)}..."
        for feature, arg of features
          continue unless arg? and arg

          # @invoke 'enable', feature: feature, options: arg
          #   .then (output) ->

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
      target = input.get 'feature'
      feature = @access "features.#{target}"
      unless feature?
        feature = new (@load "features/#{target}") null, this
        (@access 'features').push handler
      handler.enable()
      next()
