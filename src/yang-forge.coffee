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
    @output = schema = Core """
      module #{pkg.name} {
        namespace "urn:corenova:yang:#{pkg.name}";
        prefix #{pkg.name};
        yang-version 1.1;

        organization "#{pkg.homepage}";
        description "#{pkg.description}";
      }
    """
    if pkg.author?
      schema.extends Yang "contact \"#{pkg.author.name} <#{pkg.author.email}> (#{pkg.author.url})\"";
    main = Yang.compose obj, tag: 'main'
    schema.extends main

  'grouping(core-essence)/import': (pkg) ->
    debug? "[Core:import] using #{pkg.name}@#{pkg.version}"
    Core = @get('..')
    dest = path.resolve '/tmp/forge', Core.id
    @output = co =>
      ref = yield pkg.extract dest: dest
      schema = yield Core.compose require(dest), pkg
      debug? schema.toString()
      debug? Core.module.map (x) -> x.tag
      return Core.use schema

  '/forge:store': -> @content ?= core: []

  import: ->
    @output = co =>
      res = yield @in('/npm:registry/query').do @input
      cores = yield res.package.map (pkg) => @in('/forge:create').do pkg
      debug? "[import] merging #{cores.length} core(s) into internal store"
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
