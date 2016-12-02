require 'yang-js'
debug = require('debug')('yang-forge:npm') if process.env.DEBUG?
co = require 'co'
fs = require 'co-fs'
semver = require 'semver'
detect = require 'detective'
registry = require './feature/remote-registry'

# put it in npm-utils
person2obj = (str) ->
  return str unless typeof str is 'string'
  pattern = /^([\w,. ]+)(?:\s<(.+?@.+?)>)?\s*(?:\((.+?)\))?$/
  [ m, name, email, url ] = src.author.match pattern
  name:  name
  email: email
  url:   url

chooseFormat = (x) ->
  if typeof x is 'string' then value: x
  else x

dependencies2list = (obj) ->
  return unless obj instanceof Object
  name: k, source: v for k, v of obj

scripts2list = (obj) ->
  return unless obj instanceof Object
  action: k, command: v for k, v of obj
  
module.exports = require('../schema/node-package-manager.yang').bind {

  'feature(remote-registry)': -> @content ?= registry
  
  'grouping(packages-list)/package/serialize': ->
    manifest = @parent.toJSON(false)
    # TODO need to convert back to package.json format

  '/specification': ->
    @content ?=
      keywords: [
        'name', 'version', 'license', 'description', 'homepage', 'bugs', 'repository', 'config'
        'main', 'author', 'keywords', 'maintainers', 'contributors', 'dist'
        'dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies', 'bundleDependencies'
        'main', 'files', 'directories', 'scripts', 'bin', 'engines'
        'os', 'cpu', 'preferGlobal', 'private', 'publishConfig'
      ]

  '/policy': -> @content ?= cache: {}

  '/registry': -> @content ?= project: [], package: []

  '/registry/project/update': ->
    downloads = @in('../downloads')
    registry.stat @get('../name')
    .then (stat) -> downloads.content = stat

  '/registry/project/latest': ->
    modified = @get('../modified')
    @content = @get("../release[timestamp = '#{modified}']/version")
  '/registry/project/created': ->
    @content ?= @get('../release[1]').timestamp
  '/registry/project/modified': ->
    releases = @get('../release')
    @content = releases[releases.length-1].timestamp
  '/registry/project/releases-count': ->
    @content = @get('../release').length
  '/registry/project/release/manifest': ->
    name = @get('../../../name')
    version = @get('../version')
    unless @content?
      match = @in("/npm:registry/package/#{name}+#{version}")
      @content = "#{match.path}" if match?

  '/registry/package/source': ->
    shasum = @get("../dist/shasum")
    match = @in("/npm:registry/source/#{shasum}")
    @content = "#{match.path}" if match?

  '/registry/package/scan': ->
    { name, version, main, dependencies } = @get('..')
    main = path.normalize main.source
    srcref = @get('../source')
    debug? "[scan(#{name}@#{version})] using #{main} from #{srcref}"
    @output = co =>
      archive = @get(srcref)
      main = archive.$("file[name = '#{main}']")
      yield main.scan()
      seen = {}
      deps = archive.$("file/imports").filter (x) -> x?
      deps = [].concat(deps...).filter (x) -> not seen[x] and seen[x] = true
      debug? "[scan(#{name}@#{version})] found #{deps.length} pkg dependencies: #{deps}"
      dependencies.used = deps
      dependencies.scanned = true
      debug? dependencies

  '/registry/package/dependencies/unused': ->
    requires = @get('../required/name') ? []
    used = @get('../used') ? []
    @content = requires.filter (x) -> used.indexOf(x) < 0

  '/registry/source': ->
    unless @content?
      debug? "[#{@path}] update"
      cachedir = @get('/npm:policy/cache/directory')
      keys = @get('/npm:registry/package/dist/shasum')
      return unless keys?
      keys = [ keys ] unless Array.isArray keys
      @content = keys.map (x) -> name: x
      
  # TODO: below should be bound to 'file-system' module
  '/registry/source/files-count': ->
    @content ?= @get('../file')?.length
  '/registry/source/files-size': ->
    @content ?= @get('../file')?.reduce ((size, i) -> size += i.size), 0
  '/registry/source/file/read': ->
    cachedir = @get('/npm:policy/cache/directory')
    archive  = @get('../../../name')
    entry    = @get('../name')
    filename = path.resolve cachedir, archive, entry
    debug? "[read(#{entry})] retrieving from the file system"
    @output = co -> data: yield fs.readFile filename, 'utf-8'

  '/registry/source/file/scan': ->
    files = @in('../../../file')
    entry = @get('..')
    basedir = path.join entry.name, '..'
    isLocal = @schema.lookup('typedef','local-file-dependency').convert
    
    @output = co =>
      debug? "[scan(#{entry.name})] enter (scanned = #{entry.scanned})"
      return scanned: true if entry.scanned
      file = yield @in('../read').do()
      seen = {}
      try requires = detect(file.data).filter (x) -> not seen[x] and seen[x] = true
      catch e then @throw "unable to detect dependencies on #{entry.name}"
        
      debug? "[scan(#{entry.name})] requires: #{requires}"
      imports  = []
      includes = []
      matches = []
      for dep in requires
        debug? "[scan(#{entry.name})] resolving #{dep}"
        local = try isLocal dep catch then false
        unless local
          debug? "[scan(#{entry.name})] skip external dependency: #{dep}"
          imports.push dep
          continue
        dep = path.join basedir, dep
        for check in [ dep, dep+'.js', path.join(dep,'index.js') ]
          debug? "[scan(#{entry.name})] checking #{check}"
          match = files.in(".[name = '#{check}']")
          break if match?
        unless match?
          @throw "unable to resolve local #{dep} for #{entry}"
        debug? "[scan(#{entry.name})] found local dependency: #{check}"
        includes.push check
        matches.push match
      debug? "[scan(#{entry.name}] found #{imports.length} imports and #{includes.length} includes"
      entry.__.merge { scanned: true, imports: imports, includes: includes }, force: true
      yield matches.map (x) -> x.in('scan').do()
      scanned: true
        
  '/registry/projects-count': -> @content = @get('../project')?.length
  '/registry/packages-count': -> @content = @get('../package')?.length
  '/registry/sources-count':  -> @content = @get('../source')?.length

  # Registry Actions

  '/registry/sync': ->
    parse    = @in('/npm:parse')
    projects = @in('/npm:registry/project')
    packages = @in('/npm:registry/package')
    sources  = @in('/npm:registry/source')
    cachedir = @get('/npm:policy/cache/directory')

    isLocal = @schema.lookup('typedef','local-file-dependency').convert

    # recursively discover new packages from registry
    seen = {}
    discover = co.wrap (pkgs...) ->
      pkgs = pkgs.map (pkg) -> "#{pkg.name}@#{pkg.source}"
      pkgs = pkgs.filter (pkg) -> not seen[pkg] and seen[pkg] = true
      debug? "[sync] checking npm registry for #{pkgs}"
      pkgs = yield registry.view pkgs...
      debug? "[sync] match #{pkgs.length} package manifests from npm registry"
      pkgs = yield pkgs.map (pkg) -> parse.do source: pkg
      deps = pkgs.reduce ((a, pkg) ->
        return a unless pkg.dependencies.required?
        a.concat pkg.dependencies.required.filter (x) ->
          try return false if isLocal x.source
          return true
      ), []
      return pkgs unless deps.length
      return pkgs.concat yield discover deps...
      
    @output = co =>
      pkgs = yield discover @input.package...
      pkgs = pkgs.filter (pkg) -> not packages.in("#{pkg.name}+#{pkg.version}")?
      debug? "[sync] found #{pkgs.length} new package manifests"
      srcs = yield registry.fetch cachedir, pkgs...

      debug? "[sync] merging #{pkgs.length} package(s) into internal registry"
      packages.merge pkgs, force: true
      debug? "[sync] merging #{srcs.length} source(s) into internal registry"
      sources.merge srcs, force: true
      
      seen = {}
      projs = pkgs.filter (pkg) ->
        return false if projects.in(pkg.name)? or seen[pkg.name]
        seen[pkg.name] = true
      # TODO: need to update release(s) if different
      projs = projs.map (pkg) ->
        { versions=[], time={} } = pkg.extras
        name: pkg.name
        release: versions.map (ver) ->
          version: ver
          timestamp: time[ver] ? time[ver.replace('-','')]
      debug? "[sync] merging #{projs.length} project(s) into internal registry"
      projects.merge(projs, force: true).in('update')?.forEach (f) -> f.do()
      return {
        projects: projs.length
        packages: pkgs.length
        sources: srcs.length
      }

  '/registry/query': ->
    { name, source } = @input
    packages = @in('/npm:registry/package')
    @output = co =>
      yield @in('/npm:registry/sync').do package: [ @input ]
      project = @get("/npm:registry/project/#{name}")
      source = project.latest if source is 'latest'
      res = project.release
        .filter (rev) -> semver.satisfies rev.version, source
        .map (rev) => @get(rev.manifest)
      package: res

  # Module Remote Procedure Operations

  parse: ->
    src = switch typeof @input.source
      when 'string' then JSON.parse @input.source
      else @input.source

    # bypass parse if already matches schema
    match = @get("/registry/package/#{src.name}+#{src.version}")
    return (@output = match) if match?
    return (@output = src) if src.policy?

    debug? "parsing '#{src.name}@#{src.version}' package into package-manifest data model"

    keywords = @get('/specification/keywords')
    extras = {}
    extras[k] = v for k, v of src when k not in keywords

    @output = 
      name:        src.name
      version:     src.version
      license:     src.license
      description: src.description
      homepage:    src.homepage
      bugs:        chooseFormat src.bugs
      repository:  chooseFormat src.repository
      config:      src.config
      main:
        source:    src.main
      author:      chooseFormat src.author
      keywords:    src.keywords
      maintainers: src.maintainers
      contributor: src.contributors?.map? (x) -> chooseFormat x
      dist:        src.dist
      dependencies:
        required:    dependencies2list src.dependencies
        development: dependencies2list src.devDependencies
        optional:    dependencies2list src.optionalDependencies
        peer:        dependencies2list src.peerDependencies
        bundled:     src.bundledDependencies ? src.bundleDependencies
      assets:
        man:         src.man
        files:       src.files
        directories: src.directories
        script:      scripts2list src.scripts
        executable: switch typeof src.bin
          when 'string' then [ value: src.bin ]
          else dependencies2list src.bin
      policy:
        engine:  dependencies2list src.engines
        os:      src.os
        cpu:     src.cpu
        global:  src.preferGlobal
        private: src.private
        publishing: src.publishConfig
      extras: extras
      
}
