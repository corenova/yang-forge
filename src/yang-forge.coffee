# yang-forge - bound schema for 'yang-forge.yang'
debug = require('debug')('yang-forge') if process.env.DEBUG?

Yang = require('yang-js')
uuid = require('uuid')
co = require 'co'
path = require 'path'

module.exports = require('../schema/yang-forge.yang').bind {

  'grouping(core-essence)/id': -> @content ?= uuid()
  
  'grouping(core-essence)/compose': (obj, pkg) ->
    debug? "[Core:compose] using #{pkg.name}@#{pkg.version}"
    Core = @get('..')
    # TODO: check if obj is Yang
    main = Yang.compose exports: obj, tag: 'main'

    contact = switch
      when pkg.author?.value? then pkg.author.value
      when pkg.author?.name?  then "#{pkg.author.name} <#{pkg.author.email}> (#{pkg.author.url})"
      else pkg.maintainers.join "\n"
      
    reference = switch
      when pkg.repository?.value? then pkg.repository.value
      when pkg.repository?.url?   then pkg.repository.url
      when pkg.dist?.tarball?     then pkg.dist.tarball
      else pkg.version
    
    @output = (Core """
      module #{pkg.name} {
        namespace "urn:corenova:yang:#{pkg.name}";
        prefix #{pkg.name};
        yang-version 1.1;

        organization "#{pkg.homepage}";
        description "#{pkg.description}";
        contact "#{contact}";
        reference "#{reference}";
      }
    """).extends main

  'grouping(core-essence)/import': (pkg) ->
    debug? "[Core:import] using #{pkg.name}@#{pkg.version}"
    Core = @get('..')
    dest = path.resolve '/tmp/yang-forge', "#{pkg.name}@#{pkg.version}"
    importDependency = co.wrap (dep) =>
      debug? "[importDependency] #{dep.name}"
      # for sub in dep.module ? []
      #   debug? "[importDependency] checking sub #{sub.name}"
      #   yield importDependency sub
      #yield dep.module.map importDependency if dep.module?
      #return Core if Core.module?.some (x) -> x.tag is dep.name
      try main = require path.join dest, 'node_modules', dep.name
      catch e
        @throw "unable to require module for #{dep.name}@#{dep.version} from #{dest}", e
      depkg = @get("/npm:registry/package/#{dep.name}+#{dep.version}")
      schema = yield Core.compose main, depkg
      debug? "[importDependency] got schema for #{dep.name}"
      return Core.use schema
      
    @output = co =>
      extracted = yield pkg.extract dest: dest
      try main = require(dest)
      catch e
        # broken build?
        @throw "unable to require module for #{pkg.name}@#{pkg.version} from #{dest}", e
      yield extracted.module.map importDependency
      schema = yield Core.compose main, pkg
      return Core.use schema

  '/forge:store': -> @content ?= core: []

  import: ->
    @output = co =>
      res = yield @in('/npm:registry/query').do @input
      cores = yield res.package.map (pkg) => @in('/forge:create').do pkg
      cores = cores.map (x) -> x.core
      debug? "[import] merging #{cores.length} core(s) into internal store"
      cores.forEach (core) ->
        debug? core.module
      res = @in('/forge:store/core').merge cores, force: true
      return cores: res.content.map (core) -> "#{core.__.path}"
  
  create: (pkg) ->
    debug? "[create] generating core for #{pkg.name}@#{pkg.version}"
    @output = core:
      class Core extends Yang
        @module: []
    @output = co =>
      debug? "[create] using Core with existing #{Core.module.length} module(s)"
      yield Core.import pkg
      debug? "[create] Core now contains #{Core.module.length} module(s)"
      return core: Core
}
