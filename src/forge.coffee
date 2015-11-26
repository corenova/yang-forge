console = (require 'clim') '[forge]'
unless process.stderr?
  process.stderr = write: ->
if process.env.yfc_debug?
  console.debug = console.log
else
  console.log = ->
  
{
  promise, synth, yaml, coffee, path, fs, events
  request, url, indent, traverse, tosource, treeify, js2xml
} = require './components'

coffee.register?()

class Forge extends (require './compiler')
  require: require

  class Forgery extends synth.Object
    @set synth: 'source'
    @mixin events.EventEmitter

    @toSource: (opts={}) ->
      source = @extract()
      delete source.bindings

      source = (traverse source).map (x) ->
        if synth.instanceof x
          obj = x.extract 'overrides'
          synth.copy obj, x.get 'bindings'
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
              @update synth.objectify '!js/function', tosource x
          JSON.stringify source, null, opts.space
        when 'tree' then treeify.asTree source, true
        else
          source
      switch opts.encoding
        when 'base64' then (new Buffer source).toString 'base64'
        else source

    require: require

    attach: (key, val) -> super; @emit 'attach', arguments...

    connect: (to, opts) ->
      @invoke (resolve, reject) ->
        socket = (require 'socket.io-client') to
        socket.on 'connect', =>
          console.log '[socket:%s] connected', socket.id
          modules = Object.keys(@properties)
          socket.once 'rooms', (rooms) ->
            rooms = rooms.filter (x) -> typeof x is 'string'
            console.log 'got rooms: %s', rooms
            # 1. join known rooms
            socket.emit 'join', rooms.filter (room) -> room in modules

            newRooms = rooms.filter (room) -> room not in modules
            if newRooms.length > 0
              # 2. request access for new rooms
              socket.emit 'knock', newRooms
          resolve socket
        socket.on 'infuse', (data) =>
          forge = @access 'yangforge'
          # infuse the modules using keys
          forge?.invoke 'infuse', data
          .then (res) -> socket.emit 'join', res.get 'modules'
          .catch (err) -> console.error err

    render: (data=this, opts={}) ->
      return data.toSource opts if Forgery.instanceof data

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

    toString: -> "Forgery:#{@meta 'name'}"

  #
  # self-forge using package.json and package.yaml
  #
  constructor: (source) ->
    return super unless source?
    if source instanceof (require 'module')
      pkgdir = path.resolve __dirname, '..'
      source = @parse '!json package.json', pkgdir: pkgdir
      source = synth.copy source, @parse '!yaml package.yaml', pkgdir: pkgdir
    return @load source,
      async: false
      hook: ->
        @mixin Forge
        @include source: @extract()

  # NOT the most efficient way to do it...
  genSchema: (options={}) ->

    fetch = (input, opts) ->
      try
        try
          data = fs.readFileSync (path.resolve opts.pkgdir, input), 'utf-8'
          pkgdir = path.dirname (path.resolve opts.pkgdir, input)
        catch
          data = fs.readFileSync (path.resolve input), 'utf-8'
          pkgdir = path.dirname (path.resolve input)
      catch then data = input
      return [ data, pkgdir ]

    yaml.Schema.create [
      new yaml.Type '!require',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) ->
          console.log "processing !require using: #{data}"
          require (path.resolve options.pkgdir, data)
      new yaml.Type '!coffee',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) -> coffee.eval? data
      new yaml.Type '!coffee/function',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) -> coffee.eval? data
        predicate: (obj) -> obj instanceof Function
        represent: (obj) -> obj.toString()
      new yaml.Type '!json',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) =>
          console.log "processing !json using: #{data}"
          [ data, pkgdir ] = fetch data, options
          @parse data, format: 'json'
      new yaml.Type '!yaml',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) =>
          console.log "processing !yaml using: #{data}"
          [ data, pkgdir ] = fetch data, options
          options.pkgdir ?= pkgdir if pkgdir?
          @parse data, format: 'yaml', pkgdir: pkgdir
      new yaml.Type '!yang',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) =>
          console.log "processing !yang using: #{data}"
          [ data, pkgdir ] = fetch data, options
          options.pkgdir ?= pkgdir if pkgdir?
          @parse data, format: 'yang', options
      new yaml.Type '!yang/extension',
        kind: 'mapping'
        resolve:   (data={}) -> true
        construct: (data) -> data
      new yaml.Type '!yfx',
        kind: 'scalar'
        resolve:   (data) -> typeof data is 'string'
        construct: (data) =>
          console.log "processing !yfx executable archive (just treat as YAML for now)"
          [ data, pkgdir ] = fetch data, options
          options.pkgdir ?= pkgdir if pkgdir?
          @parse data, format: 'yaml', pkgdir: pkgdir
    ]

  parse: (source, opts={}) ->
    return source unless typeof source is 'string'

    input = source
    source = switch opts.format
      when 'yang' then super source
      when 'json' then JSON.parse source
      else yaml.load source, schema: @genSchema opts

    unless source? and typeof source is 'object'
      throw @error "unable to parse requested source data: #{input}"

    # XXX - below doesn't belong here...
    if source.dependencies?
      source.require = (arg) -> @dependencies[arg]
    return source

  preprocess: (source, opts={}) ->
    source = @parse source, opts if typeof source is 'string'
    return source unless source instanceof Object

    # determine whether source is YAML or YANG output... a bit hackish
    # but YANG parse output always has ONE primary root element
    # need a better way to know the actual VALUE of the source
    if Object.keys(source).length is 1
      source = schema: source

    if source.schema?
      source.parent = @source
      source.pkgdir = opts.pkgdir ? @source?.pkgdir
      source.schema = super source.schema, source
      delete source.parent
    return source

  compile: (source, opts={}) ->
    source = @preprocess source, opts
    if source?.schema?
      try
        source.parent = @source
        model = super source.schema, source
        delete source.parent
        for own name of model
          source.name ?= name
          source.description ?= model[name].get? 'description'
          break; # TODO: should only be ONE here?
        metadata = synth.extract.apply source, [
          'name', 'version', 'description', 'license', 'schema', 'dependencies',
          'extension', 'feature', 'keywords', 'rpc', 'typedef', 'complex-type',
          'pkgdir', 'module', 'config'
        ]
        source = ((synth Forgery, opts.hook) metadata).bind model
      finally
        delete source.parent
    return source

  # performs load of a target source, defaults to async: true but can be optionally set to false
  # allows 'source' as array but ONLY if async is true
  load: (source, opts={}, resolve, reject) ->
    unless opts.async is false
      return promise.all (@load x, opts for x in source) if source instanceof Array
      return @invoke arguments.callee, source, opts unless resolve? and reject?
    else resolve = (x) -> x
    source = @compile source, opts unless synth.instanceof source
    resolve switch
      when (synth.instanceof source)
        console.log "[load:#{source.get 'name'}] creating a new instance"
        new source (source.get 'config')
      else source

  # performs async import of a target source path, accepts 'source' as array
  # ALWAYS async, cannot be set to async: false
  import: (source, opts={}, resolve, reject) ->
    return promise.all (@import x, opts for x in source) if source instanceof Array
    return @invoke arguments.callee, source, opts unless resolve? and reject?

    return resolve source if source instanceof Forgery
    return reject 'must pass in string(s) for import' unless typeof source is 'string'

    opts.async = true
    return resolve @load source if /\n|\r/.test source

    url = url.parse source
    source = switch url.protocol
      when 'yf:','forge:'
        forgery = opts.forgery ? (@get 'yangforge.runtime.forgery') ? (@meta 'forgery')
        "#{forgery}/registry/modules/#{url.hostname}"
      when 'http:','https:'
        source
      when 'gh:','github:'
        "https://raw.githubusercontent.com/#{url.hostname}#{url.pathname}"
      else
        url.protocol = 'file:'
        url.pathname
    tag = switch (path.extname source)
      when '.yang' then '!yang'
      when '.json' then '!json'
      when '.yaml' then '!yaml'
      else '!yfx'

    switch url.protocol
      when 'file:'
        try resolve @load "#{tag} #{source}"
        catch err then reject err
      when 'yf:','forge:'
        # we initiate a TWO stage sequence, get metadata and then get binary
        request
        .head source
        .end (err, res) =>
          if err? or !res.ok
            return reject err ? "unable to retrieve #{source} metadata"
          chksum = res.body.checksum
          request
          .get source
          .end (err, res) =>
            if err? or !res.ok
              return reject err ? "unable to retrieve #{source} binary data"
            # TODO: verify checksum
            resolve @load "#{tag} |\n#{indent res.text, ' ', 2}"
      else
        # here we use needle to get the remote content
        console.log "fetching remote content at: #{source}"
        request
        .get source
        .end (err, res) =>
          if err? or !res.ok then reject err
          else resolve @load "#{tag} |\n#{indent res.text, ' ', 2}"

  # TBD
  export: (input=this) ->
    console.assert input instanceof Object, "invalid input to export module"
    console.assert typeof input.name is 'string' and !!input.name,
      "need to pass in 'name' of the module to export"
    format = input.format ? 'json'
    m = switch
      when (synth.instanceof input) then input
      else @resolve 'module', input.name
    console.assert (synth.instanceof m),
      "unable to retrieve requested module #{input.name} for export"

    obj = m.extract 'name', 'schema', 'map', 'extensions', 'importers', 'exporters', 'procedures'
    for key in [ 'extensions', 'importers', 'procedures' ]
      obj[key]?.toJSON = ->
        @[k] = tosource v for k, v of this when k isnt 'toJSON' and v instanceof Function
        this

    return switch format
      when 'json' then JSON.stringify obj

module.exports = new Forge (window?.source ? module)
