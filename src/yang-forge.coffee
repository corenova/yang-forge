# yang-forge - bound schema for 'yang-forge.yang'
debug = require('debug')('yang-forge') if process.env.DEBUG?

Yang = require('yang-js')
uuid = require('uuid')
co = require 'co'
path = require 'path'

module.exports = require('../schema/yang-forge.yang').bind {

  'grouping(core-essence)/id': -> @content ?= uuid()

  '/npm:registry/package/forge:build': ->
    { name, version } = pkg = @get('..')
    if pkg.$('forge:core')? and not @input.force
      return @output = pkg.$('forge:core/exports')
    
    @output = co =>
      dest = path.resolve '/tmp/yang-forge', pkg['@key']
      extracted = yield pkg.extract dependencies: true, dest: dest
      try main = require(dest)
      catch e
        # broken build?
        @throw "unable to require module for #{name}@#{version} from #{dest}", e

      debug? "[forge:build] generating Core for #{name}@#{version}"
      class Core extends Yang
        @module: []

      # schedule dependency core generation to take place async in the background
      process.nextTick co.wrap =>
        res = yield extracted.module.map (m) =>
          @in("/npm:registry/package/#{m.name}+#{m.version}/forge:build").do()
        Core.use schema for schema in res when schema instanceof Yang
        Core.exports.compile() # we compile the primary schema once all dependency schemas are loaded

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

      debug? "[forge:build] generating Core.exports for #{name}@#{version}"
      Core.exports = (Core.parse """
        module #{pkg.name} {
          namespace "urn:corenova:yang:#{pkg.name}";
          prefix #{pkg.name};
          yang-version 1.1;

          organization "#{pkg.homepage}";
          description "#{pkg.description}";
          contact "#{contact}";
          reference "#{reference}";
        }
      """, compile: false)
      .extends dependencies.map (x) -> Core.parse "import #{x} { prefix #{x}; }", compile: false
      .extends Yang.compose { exports: main }, tag: 'main'
      debug? "[forge:build] generated Core.exports for #{name}@#{version}"
      pkg.$('forge:core',true).set Core, force: true
      return Core.exports

  '/forge:store':      -> @content ?= core: []
  '/forge:store/core': -> @content = @get('/npm:registry/package/forge:core')

  import: ->
    @output = co =>
      start = new Date
      @input.sync = true
      res = yield @in('/npm:registry/query').do @input
      cores = yield res.package.map (pkg) =>
        @in("/npm:registry/package/#{pkg.name}+#{pkg.version}/forge:build").do()
      console.log "[import] took #{((new Date) - start)/1000} seconds"
      return cores: cores.map (core) -> core.toString()
  
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
