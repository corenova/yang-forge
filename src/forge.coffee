# forge - load and build components

Composer = require './composer'
Core     = require './core'
url      = require 'url'

class Maker extends Composer
  # accepts: variable arguments of Core definition schema(s)
  # returns: Promise for a new Forge with one or more generated Core(s)
  load: ->
    super
    .then (res) =>
      res = [].concat res...
      for core in res when core?.get?
        console.log "[Maker:load] define a new core '#{core.get 'name'}'"
        @define 'core', core.get('name'), core
      return this

  compose: (input, origin) ->
    console.log "[Maker:compose] entered with:"
    console.log input
    input = Core.load input
    return @load input if input instanceof url.Url

    console.log "[Maker:compose] #{input.name}"
    (new Container this)
    .use origin: origin
    .load input.contains...
    .then (res) -> (new Linker res).load input.links...
    .then (res) -> (new Provider res).load input.provides...
    .then (res) ->
      class extends Core
        @provider = res
        @merge input
        @set origin: origin
        @bind res.map
    .catch (err) => console.error err; throw @error err

class Container extends Maker
  # enable inspecting inside defined core(s) during lookup
  resolve: ->
    match = super
    return match unless @parent?
    unless match?
      for name, core of (super 'core') when core?.provider?
        match = core.provider.resolve? arguments...
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
  fetch: (link) -> super

class Provider extends Composer
  load: -> super.then (res) =>
    res = [].concat res...
    console.log res
    @use (@compile x) for x in res
    return this

  compose: (x) ->
    if typeof x is 'string' then @parse x
    else x

class Forge extends Container

  create: (cname, opts={}) ->
    opts.transform ?= true
    try
      console.log "[create:#{cname}] creating a new #{cname} core instance"
      core = @resolve 'core', cname
      # if opts.transform
      #   for xform in (core.get 'transforms') ? []
      return new core opts.config
    catch e
      console.error e
      return new Core config

#
# declare exports
#
exports = module.exports = new Forge
exports.Forge = Forge # for class-def validation
exports.Core  = Core  # for class-def validation
