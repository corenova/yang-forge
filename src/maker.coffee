# maker - load and compose cores

console.debug ?= console.log if process.env.yang_debug?

Composer = require './composer'
Core     = require './core'
url      = require 'url'

class Maker extends Composer
  # accepts: variable arguments of Core definition schema(s)
  # returns: Promise for a new Forge with one or more generated Core(s)
  load: ->
    super
    .then (res) =>
      res = ([].concat res).filter (e) -> e? and !!e
      for core in res when core.constructor is Core.constructor
        { name, origin } = core.extract 'name', 'origin'
        type = origin.protocol.replace ':',''
        type ?= 'core'
        console.debug? "[Maker:load] define a new '#{type}:#{name}'"
        @define type, name, core
      return this

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

class Container extends Maker
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

  # special npm:? link processing
  fetch: (link) -> switch link.protocol
    when 'npm:'
      if /^[\.\/]/.test link.pathname
        unless /package.json$/.test link.pathname
          link.pathname += '/package.json'
        (super url.parse "file:#{link.pathname}")
        .then (res) -> JSON.parse res
    when 'core:'
      if /^[\.\/]/.test link.pathname
        (super url.parse "file:#{link.pathname}")
        .catch ->
          (super url.parse "file:#{link.pathname}/core.yaml")
    when 'feature:'
      (super url.parse "require:#{link.pathname}")
    else
      super

class Linker extends Container
  # TODO: special magnet:? link processing
  fetch: (link) ->  switch link.protocol
    when 'machine:'
      (super url.parse "https://#{link.host}:37713")
      .catch ->
        name: 'interlink.io'
        description: 'placeholder'
    else
      super

class Provider extends Composer
  load: -> super.then (res) =>
    res = ([].concat res).filter (e) -> e? and !!e
    @use (@compile x) for x in res
    return this

  compose: (x) ->
    if typeof x is 'string' then @parse x
    else x

exports = module.exports = Maker
exports.Container = Container
exports.Core = Core
