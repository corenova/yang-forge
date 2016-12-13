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
    main = Yang.compose { exports: obj }, tag: 'main'

    contact = switch
      when pkg.author?.value? then pkg.author.value
      when pkg.author?.name?  then "#{pkg.author.name} <#{pkg.author.email}> (#{pkg.author.url})"
      else pkg.maintainers.join "\n"
      
    reference = switch
      when pkg.repository?.value? then pkg.repository.value
      when pkg.repository?.url?   then pkg.repository.url
      when pkg.dist?.tarball?     then pkg.dist.tarball
      else pkg.version

    dependencies = pkg.dependencies.$('required[used = true()]/name') ? []
    dependencies = [ dependencies ] unless Array.isArray dependencies
    @output = (Core.parse """
      module #{pkg.name} {
        namespace "urn:corenova:yang:#{pkg.name}";
        prefix #{pkg.name};
        yang-version 1.1;

        organization "#{pkg.homepage}";
        description "#{pkg.description}";
        contact "#{contact}";
        reference "#{reference}";
      }
    """)
    .extends dependencies.map (x) -> Core.parse "import #{x} { prefix #{x}; }"
    .extends main

  'grouping(core-essence)/import': (pkg) ->
    pkgkey = pkg.name + '@' + pkg.version
    debug? "[Core:import] using #{pkgkey}"
    Core = @get('..')
    dest = path.resolve '/tmp/yang-forge', pkgkey

    # TODO: importDependency should perform forge:import
    importDependency = co.wrap (dep) =>
      debug? "[importDependency] #{dep.name}@#{dep.version}"
      try main = require path.join dest, 'node_modules', dep.name
      catch e
        @throw "unable to require module for #{dep.name}@#{dep.version} from #{dest}", e
      depkg = @get("/npm:registry/package/#{dep.name}+#{dep.version}")
      schema = yield Core.compose main, depkg
      debug? "[importDependency] got schema:"
      debug? schema
      return Core.use schema
      
    @output = co =>
      extracted = yield pkg.extract dest: dest
      try main = require(dest)
      catch e
        # broken build?
        @throw "unable to require module for #{pkg.name}@#{pkg.version} from #{dest}", e
      yield importDependency dep for dep in extracted.module
      schema = yield Core.compose main, pkg
      debug? "[Core:import] got schema:"
      debug? schema
      return Core.use schema

  '/forge:store': -> @content ?= core: []

  import: ->
    @output = co =>
      res = yield @in('/npm:registry/query').do @input
      cores = yield res.package.map (pkg) =>
        pkg = @get("/npm:registry/package/#{pkg.name}+#{pkg.version}")
        @in('/forge:create').do pkg
      cores = cores.map (x) -> x.core
      debug? "[import] merging #{cores.length} core(s) into internal store"
      res = @in('/forge:store/core').merge cores, force: true
      return cores: res.content.map (core) -> "#{core.__.path}"
  
  create: (pkg) ->
    debug? "[create] generating core for #{pkg.name}@#{pkg.version}"
    @output = core:
      class Core extends Yang
        @module: []
    @output = co =>
      yield Core.import pkg
      debug? "[create] Core contains #{Core.module.length} module(s)"
      return core: Core
}
