# yang-forge - bound schema for 'yang-forge.yang'
require 'yang-js'
debug = require('debug')('yang-forge') if process.env.DEBUG?
co = require 'co'
path = require 'path'

module.exports = require('../schema/yang-forge.yang').bind {

  '/npm:registry/package/forge:build': ->
    pkg = @get('..')
    base = path.join @input.base, pkg.name
    @output = co =>
      debug? "[build(#{pkg.name}@#{pkg.version})] using #{pkg.source}"
      res = yield pkg.scan()
      archive = @get(pkg.source)
      yield archive.extract to: base, filter: { tagged: true }
      base = path.join base, 'node_modules'
      for dep in res.dependency
        debug? "[build(#{pkg.name}@#{pkg.version})] building #{dep.name} #{dep.version}"
        depkg = @get("/npm:registry/package/#{dep.name}+#{dep.version}")
        yield depkg.$('forge:build',true).do base: base
    
      # wrapper: [
      #   '(function (exports, require, module, __filename, __dirname) { '
      #   '\n});'
      # ]
  
  transform: ->
    @output =
      @in('/npm:transform').do @input
      .then (output) ->
        debug? "transforming '#{output.name}' package into core-manifest data model"
        if output.extras?.models instanceof Object
          output.model = (name: k, source: v for k, v of output.extras.models)
        return output
}
