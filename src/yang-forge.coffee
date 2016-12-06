# yang-forge - bound schema for 'yang-forge.yang'
Yang = require 'yang-js'
debug = require('debug')('yang-forge') if process.env.DEBUG?
co = require 'co'
path = require 'path'

module.exports = require('../schema/yang-forge.yang').bind {

  '/npm:registry/package/forge:load': ->
    pkg = @get('..')
    dest = path.join @input.dest, "#{pkg.name}@#{pkg.version}"
    @output = co =>
      debug? "[build(#{pkg.name}@#{pkg.version})] unpack to #{dest}"
      res = yield pkg.extract dest: dest
      schema = Yang.compose require(dest), tag: 'main'
      
    
      # wrapper: [
      #   '(function (exports, require, module, __filename, __dirname) { '
      #   '\n});'
      # ]

  '/store/import': ->
    cachedir = @get('/forge:policy/cache/directory')
    @output = co =>
      res = yield @in('/npm:registry/query').do @input
      cores = []
      for pkg in res.package
        dest = path.join cachedir, "#{pkg.name}@#{pkg.version}"
        ref = yield pkg.extract dest: dest
        core = Yang """
          module #{pkg.name} {
            namespace "urn:corenova:yang:#{pkg.name}";
            prefix #{pkg.name};
            yang-version 1.1;

            organization "#{pkg.homepage}";
            contact "#{pkg.author.name} <#{pkg.author.email}> (#{pkg.author.url})";
            description "#{pkg.description}";
            

          }
        """
        core.extends
          
        
        schema = Yang.compose require(dest), tag: 'main'
        
        
      yield res.package.map (pkg) ->
        
      for pkg in res.package
        
  
  create: ->
    @output =
      @in('/npm:transform').do @input
      .then (output) ->
        debug? "transforming '#{output.name}' package into core-manifest data model"
        if output.extras?.models instanceof Object
          output.model = (name: k, source: v for k, v of output.extras.models)
        return output
}
