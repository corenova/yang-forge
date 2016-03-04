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
      when input instanceof url.Url
        input = @normalize input
        (@fetch input).then (res) => resolve @compose res, input
      else resolve @compose input

  compose: (input, origin) -> throw @error "must be overriden by implementing class"

  # handles relative link paths if 'origin' is defined
  normalize: (link) ->
    origin = @resolve 'origin'
    origin = url.parse origin if typeof origin is 'string'
    return link unless origin instanceof url.Url

    origin.protocol ?= 'file:'
    if /^\./.test link.pathname
      link.pathname = path.normalize (path.dirname(origin.pathname) + link.pathname)
    return link

  # helper routine for fetching remote assets
  fetch: (link) -> new promise (resolve, reject) =>
    return reject "attempting to fetch invalid link" unless link instanceof url.Url
    switch link.protocol
      when 'http:','https:'
        request.get(link).end (err, res) ->
          if err? or !res.ok then reject err
          else resolve res.text
      when 'file:'
        fs.readFile (path.resolve link.pathname), 'utf-8', (err, data) ->
          if err? then reject err
          else resolve data
      else
        reject "unrecognized protocol '#{link.protocol}' for retrieving #{url.format link}"

class Maker extends Composer
  # accepts: variable arguments of Core definition schema(s)
  # returns: Promise for a new Forge with one or more generated Core(s)
  load: -> super.then (res) =>
    res = [ res ] unless res instanceof Array
    @define 'core', core.get('name'), core for core in res when core?.get?
    return this

  compose: (input, origin) ->
    input = Core.load input
    (new Container this)
    .use origin: origin
    .load input.contains...
    .then (res) -> (new Linker res).load input.links...
    .then (res) -> (new Provider res).load input.provides...
    .then (res) ->
      class extends Core
        @compiler = res
        @merge input
        @set origin: origin
        @bind res.map

class Container extends Maker
  # enable inspecting inside defined core(s) during lookup
  resolve: ->
    match = super
    unless match?
      for name, core of (super 'core') when core?.compiler?
        match = core.compiler.resolve? arguments...
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
    else
      super

class Linker extends Container
  # TODO: special magnet:? link processing
  fetch: (link) -> super

class Provider extends Composer
  load: -> super.then (res) =>
    res = [ res ] unless res instanceof Array
    @use (@compile x) for x in res
    return this

  compose: (x) ->
    if typeof x is 'string' then @parse x
    else x

class Forge extends Maker

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
