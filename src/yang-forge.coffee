# yang-forge - bound schema for 'yang-forge.yang'
require 'yang-js'
debug = require('debug')('yang-forge') if process.env.DEBUG?

module.exports = require('../yang-forge.yang').bind {

  'grouping(package-manifest)/stats': ->
    revisions = @get('../revision')
    @content =
      created:  revisions[0].timestamp
      modified: revisions[revisions.length-1].timestamp
      'revision-count': revisions.length

  'grouping(package-manifest)/dependencies/required/is-local': ->
    try 
      @schema.locate('/typedef(local-file-dependency)').convert @get('../resolver')
      @content = true
    catch e
      @content = false
  
  'grouping(package-manifest)/dependencies/required/outdated': ->
    @content = @get('../package')?.length > 1

  transform: ->
    @output =
      @in('/npm:transform').do @input
      .then (output) ->
        debug? "transforming '#{output.name}' package into package-manifest data model"
        if typeof output.extras?.models is 'object'
          output.model = (name: k, source: v for k, v of output.extras.models)
        return output
        
  inspect: ->
    [ name, version ] = @input.package.split '@'
    debug? "inspecting '#{name}' package"
    query = @in('/npm:query')
    @output = 
      query.do package: [ name: name, source: version ]
      .then (output) => @in('/transform').do source: output.package[0]
      .then (pkg) ->
        debug? "inspecting '#{pkg.name}' package dependencies"
        query.do package: pkg.$('dependencies/required[is-local=false()]')
        .then (output) ->
          output.package.forEach (x) ->
            item = pkg.$("dependencies/required/#{x.name}")
            item.package ?= []
            item.package.push x
          return pkg

}
