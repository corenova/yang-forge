module.exports =
  @model: 'yangforge-engine'
  
  info: (input, output, done) ->
    app = @parent
    target = (input.get 'arguments')[0]
    target ?= app
    app.import target
    .then (res) ->
      output.set res.info? (input.get 'options')
      done()
    .catch (err) -> done err

  schema: (input, output, done) ->
    app = @parent
    options = input.get 'options'
    schema = (input.get 'arguments')[0]
    schema = options.eval if options.eval?
    result = switch
      when options.load
        source = app.load "!yang #{schema}", async: false
        for name, model of source.properties
          console.info "absorbing a new model '#{name}' into running forge"
          app.attach name, model
        source.constructor
      when options.compile then app.compile "!yang #{schema}"
      when options.preprocess then (app.preprocess "!yang #{schema}").schema
      else app.parse "!yang #{schema}"
    result = (app.render result, options)
    unless options.output?
      output.set result
      return done()

    output.set "output saved to '#{options.output}'"
    fs = app.require 'fs'
    fs.writeFile options.output, result, 'utf8', (err) ->
      if err? then done err else done()

  translate: (input, output, done) ->
    app = @parent
    data = (input.get 'arguments')[0]
    options = input.get 'options'

    data = app.parse "!json #{data}"
    output.set app.set(data).render app.get(), options
    # output.set app.fork ->
    #   @set data
    #   @render @get(), options

    if options.output?
      fs = require 'fs'
      fs.writeFile options.output, output.get(), 'utf8', (err) ->
        if err? then done err else done()
    else done()

  build: (input, output, done) ->
    app = @parent
    target = (input.get 'arguments')[0]
    options = input.get 'options'

    browserify = require 'browserify'

    # unless target? or target is directory
    # 1. retrieve package.json
    # 1a. if has 'dependencies' then need to issue 'npm install' do it via API?
    # 2. retrieve package.yaml
    # 3. res = browserify package
    # 4. treat target as !yfx res

    return done "must specify target input file to build" unless target?

    app.import target
    .then (res) ->
      result = res.constructor.toSource format: 'yaml'
      if options.gzip
        zlib = app.require 'zlib'
        #result = zlib.deflate result

      unless options.output?
        output.set result
        return done()

      fs = app.require 'fs'
      fs.writeFile options.output, result, 'utf8', (err) ->
        output.set "output saved to '#{options.output}'"
        if err? then done err else done()
    .catch (err) -> done err

  config: (input, output, done) ->

  infuse: (input, output, done) ->
    app = @parent
    sources = input.get 'sources'
    sources = sources.concat ((input.get 'targets').map (e) -> e.source)...
    unless sources.length > 0
      output.set 'message', 'no operation since no sources(s) were specified'
      return done()

    app.import sources
    .then (res) =>
      promises = res.reduce ((a,b) -> a.concat b.save()...), []
      @invoke promises.map (p) -> (resolve) -> resolve p
    .then (modules) ->
      for model in modules
        #console.log "<infuse> absorbing a new model '#{model.name}' into running forge"
        app.attach model.name, model
      modules
    .then (modules) ->
      output.set 'message', 'request processed successfully'
      output.set 'modules', modules.map (x) -> x.name
      #console.log "<infuse> completed"
      done()
    .catch (err) -> done err

  defuse: (input, output, done) ->
    app = @parent
    for name in input.get 'names'
      app.detach name
    output.set 'message', 'OK'
    done()

  run: (input, output, done) ->
    app = @parent
    features = input.get 'options'
    console.log "forgery firing up..."
    for name, arg of features when arg? and arg isnt false
      console.debug? "#{name} with #{arg}"
      features[name] = (app.resolve 'feature', name)?.run? this, features

    @invoke 'infuse', targets: (input.get 'arguments').map (e) -> source: e
    .then (res) =>
      modules = res.get 'modules'
      output.set "running with: " + (['yangforge'].concat modules...)
      done()
    .catch (err) -> done err

