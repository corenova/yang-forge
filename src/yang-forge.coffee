# yang-forge - bound schema for 'yang-forge.yang'
require 'yang-js'
path = require 'path'
debug = require('debug')('yang-forge') if process.env.DEBUG?

module.exports = require('../schema/yang-forge.yang').bind {

  '/npm:registry/source/file/load/output/exports': ->
      wrapper: [
        '(function (exports, require, module, __filename, __dirname) { '
        '\n});'
      ]
  
  transform: ->
    @output =
      @in('/npm:transform').do @input
      .then (output) ->
        debug? "transforming '#{output.name}' package into core-manifest data model"
        if output.extras?.models instanceof Object
          output.model = (name: k, source: v for k, v of output.extras.models)
        return output

  build: ->
    cores = @in('/forge:registry/core')
    pkg = undefined
    core = {}
    @output = 
      @in('/npm:query').do @input
      .then (output) =>
        packages = output.package
        deps = output.$('package/dependencies/required[is-local=false()]') ? []
        @in('/forge:build').do package: deps
        .then (output) -> output.core
      .then (cores) =>
        core.dependency = cores.map (core) -> core.id
        @in('/npm:fetch').do package: [ pkg ]
        .then (output) -> output.source
      .then (sources) =>

        res = cores.merge core, force: true
        
        package: pkg.id
        source: pkg.dist.shasum
        
        @in('/npm:fetch').do output
        
      .then (output) => @in('/transform').do source: output.package[0]
      .then (pkg) =>
        debug? "inspecting '#{pkg.name}' package dependencies"
        @in('/inspect').do package: pkg.$('dependencies/required[is-local=false()]')
        .then (output) -> 
          output.package.forEach (x) ->
            item = pkg.$("dependencies/required/#{x.name}")
            item.package ?= []
            item.package.push x
          return pkg
      .then (pkg) ->
        return pkg

}
