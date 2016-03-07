# Composer - promise wrapper around compiler to enable asynchronous compilations

console.debug ?= console.log if process.env.yang_debug?

promise = require 'promise'
url     = require 'url'
path    = require 'path'
fs      = require 'fs'
request = require 'superagent'

class Composer extends (require 'yang-js').Compiler
  # accepts: variable arguments of target input(s)
  # returns: Promise for one or more generated output(s)
  load: (input, rest...) ->
    return promise.all (Composer::load.call this, x for x in arguments) if arguments.length > 1
    return new promise (resolve, reject) => switch
      when not input? then resolve null
      when input instanceof url.Url
        input = @normalize input
        (@fetch input)
        .then  (res) => resolve @compose res, input
        .catch (err) => reject err
      else resolve @compose input

  compose: (input, origin) -> throw @error "must be overriden by implementing class"

  # handles relative link paths if 'origin' is defined
  normalize: (link) ->
    console.debug? "[Composer:normalize] #{url.format link}"
    origin = @resolve 'origin'
    origin = url.parse origin if typeof origin is 'string'
    return link unless origin instanceof url.Url

    origin.protocol ?= 'file:'

    target = switch
      when link.query? then link.query
      else link.pathname
    if /^\./.test target
      link.pathname = switch
        when !!(path.extname origin.pathname)
          path.normalize (path.dirname(origin.pathname) + '/' + target)
        else
          path.normalize (origin.pathname + '/' + target)
    return link

  # helper routine for fetching remote assets
  fetch: (link) -> new promise (resolve, reject) =>
    console.debug? "[Composer:fetch] #{url.format link}"
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
      when 'require:'
        resolve (require link.pathname)
      else
        reject "unrecognized protocol '#{link.protocol}' for retrieving #{url.format link}"

module.exports = Composer
