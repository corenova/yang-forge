# forge - load and build components

promise = require 'promise'
url     = require 'url'
path    = require 'path'
fs      = require 'fs'
request = require 'superagent'

Compiler = require './compiler'
Core     = require './core'

# Composer - promise wrapper around compiler to enable asynchronous compilations
class Composer extends Compiler
  # accepts: variable arguments of target input(s)
  # returns: Promise for one or more generated output(s)
  load: (input, rest...) ->
    return promise.all (@load x for x in arguments) if arguments.length > 1
    return new promise (resolve, reject) => switch
      when input instanceof url.Url then (@fetch input).then (res) => resolve @compose res, input
      else resolve @compose input

  compose: (input, origin) -> throw @error "must be overriden by implementing class"

  # helper routine for fetching remote assets
  fetch: (source) -> new promise (resolve, reject) =>
    return reject "attempting to fetch invalid Url" unless source instanceof url.Url
    switch source.protocol
      when 'http:','https:'
        request.get(source).end (err, res) ->
          if err? or !res.ok then reject err
          else resolve res.text
      when 'file:'
        fs.readFile (path.resolve source.pathname), 'utf-8', (err, data) ->
          if err? then reject err
          else resolve data
      else
        reject "unrecognized protocol '#{source.protocol}' for retrieving #{url.pathname}"

class Provider extends Composer
  load: -> super.then (res) =>
    res = [ res ] unless res instanceof Array
    @use (@compile x) for x in res
    return this

  compose: (x) -> @parse x if typeof x is 'string'

class Forge extends Composer

  class Container extends Forge
    # enable inspecting inside defined core(s) during lookup
    resolve: ->
      match = super
      unless match?
        for name, core of (super 'core') when core?.compiler?
          match = core.compiler.resolve? arguments...
          break if match?
      return match

    # special npm:? link processing
    fetch: (link) ->
      data = switch link.pathname
        when /^\./ then (super "file:#{link.pathname}")
        
      return switch link.protocol
        when 'npm:' then data.then (res) -> JSON.parse res
        else data
  
  # TODO: special magnet:? link processing
  class Linker extends Container
    fetch: (link) -> super

  # accepts: variable arguments of Core definition schema(s)
  # returns: Promise for a new Forge with one or more generated Core(s)
  load: -> super.then (res) =>
    res = [ res ] unless res instanceof Array
    @define 'core', core.get('name'), core for core in res when core?.get?
    return this

  compose: (input, origin) ->
    input = Core.load input
    (new Container this).load input.contains...
    .then (res) -> (new Linker res).load input.links...
    .then (res) -> (new Provider res).load input.provides...
    .then (res) ->
      class extends Core
        @compiler = res
        @merge input
        @set origin: origin
        @bind res.map

  create: (cname, opts={}) ->
    opts.transform ?= true
    try
      console.log "[build:#{cname}] creating a new #{cname} core instance"
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
