# forge - load and build cores

console.debug ?= console.log if process.env.yang_debug?

Composer = require './composer'
url      = require 'url'

class Forge extends Composer

  # accepts: variable arguments of Core definition schema(s)
  # returns: Promise for a new JS Object with one or more generated Core(s)
  load: (core, opts={}) ->
    super
    .then (res) =>
      res = ([].concat res).filter (e) -> e? and !!e
      for core in res when core.constructor is Core.constructor
        { name, origin } = core.extract 'name', 'origin'
        type = origin.protocol.replace ':',''
        type ?= 'core'
        console.debug? "[Maker:load] define a new '#{type}:#{name}'"
        @define type, name, core

      # from Provider...
      # @use (@compile x) for x in res

      return this

  fetch: (link) -> switch link.protocol

    when 'feature:'
      (super url.parse "require:#{link.pathname}")

    else
      super

  # Maker can also compose instances of existing Core(s)
  compose: (input, origin) ->
    console.debug? "[Maker:compose] entered with:"
    console.debug? input
    input = Core.load input
    switch
      when input instanceof url.Url then return @load input
      when input instanceof Core then return input.constructor
      when input.constructor is Core.constructor then return input
    throw @error "cannot compose a new core without name", input unless input.name?

    console.debug? "[Maker:compose] #{input.name} from #{url.format origin}"
    (new Maker this)
    .include input.includes...
    .link input.links
    .create input.provides...

    .load input.contains...
    .then (res) -> res.load input.links...
    .then (res) -> res.load input.provides...
    .then (res) ->



    (new Core this)
    .infuse input.contains...
    .



    (new Container this)
    .use origin: origin
    .load input.contains...
    .then (res) -> (new Linker res).load input.links...
    .then (res) -> (new Provider res).load input.provides...
    .then (res) ->
      input.main ?= (engine) -> @emit 'start', engine
      class extends Core
        @set name: input.name, origin: origin, provider: res
        @bind input
        @bind res.map
    .catch (err) => console.error err; throw @error err

  create: (cname, data) ->
    try
      console.debug? "[Maker:create] a new '#{cname}' core instance"
      core = @resolve 'core', cname
      return new core data, this
    catch e
      console.error e
      return new Core config

  # enable inspecting inside defined core(s) during lookup
  resolve: (type, key, opts={}) ->
    match = super
    return match unless @parent?
    unless match?
      opts.warn = false
      opts.recurse = false
      for name, core of (super 'core', undefined, opts)
        provider = core.get 'provider'
        match = provider?.resolve type, key, opts
        break if match?
    return match

  dump2: (obj, opts={}) ->
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

#
# declare exports
#
exports = module.exports = (new Forge).use FORGE_DEFAULTS...
exports.Forge = Forge # for making new Forgeries
