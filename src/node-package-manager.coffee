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
  name: k, match: v for k, v of obj

scripts2list = (obj) ->
  return unless obj instanceof Object
  action: k, command: v for k, v of obj
  
module.exports = require('../schema/node-package-manager.yang').bind {

  'feature(remote-registry)': -> @content ?= registry
  
  'grouping(packages-list)/package/serialize': ->
    manifest = @parent.toJSON(false)
    # TODO need to convert back to package.json format

  'grouping(packages-list)/package/scan': ->
    { name, version, dependencies } = pkg = @get('..')
    main = path.normalize pkg.main.source
    debug? "[scan(#{name}@#{version})] using '#{main}' from #{pkg.source}"
    @output = co =>
      return valid: true if pkg.scanned
      archive = @get(pkg.source)
      main = yield archive.resolve main
      yield main.scan tag: true
      seen = {}
      deps = archive.$("file[scanned = true()]/imports").filter (x) -> x?
      deps = [].concat(deps...).filter (x) -> not seen[x] and seen[x] = true
      debug? "[scan(#{name}@#{version})] found #{deps.length} pkg dependencies: #{deps}"
      missing = []
      for dep in deps when dep not of process.binding('natives')
        d = dependencies.$("required/#{dep}")
        if d? then d.used = true else missing.push dep
      dependencies.missing = missing
      pkg.scanned = true

      output = yield @in('/registry/query').do
        package: dependencies.$("required[used = true()]")
        filter: 'latest'
        sync: false
      yield output.package.map (pkg) -> pkg.scan()
      
      return {
        valid: true
      }

  'grouping(sources-list)/source/resolve': ->
    name = @input
    files = @in('../file')
    # TODO: handle case where 'name' is pointing at a directory with package.json
    for check in [ name, name+'.js', path.join(name,'index.js') ]
      match = files.get(".[name = '#{check}']")
      break if match?
    @output = match

  'grouping(sources-list)/source/extract': ->
    { to, essence } = @input
    

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
    { tag } = @input
    archive = @get('../../..')
    entry = @get('..')
    basedir = path.join entry.name, '..'
    isLocal = @schema.lookup('typedef','local-file-dependency').convert
    
    @output = co =>
      return valid: true if entry.scanned
      file = yield @in('../read').do()
      seen = {}
      debug? "[scan(#{entry.name})] detecting dependencies"
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
        match = yield archive.resolve dep
        unless match?
          @throw "unable to resolve local #{dep} for #{entry}"
        debug? "[scan(#{entry.name})] found local dependency: #{match.name}"
        includes.push match.name
        matches.push match
      debug? "[scan(#{entry.name}] found #{imports.length} imports and #{includes.length} includes"
      entry.__.merge { tagged: tag, scanned: true, imports: imports, includes: includes }, force: true
      
      yield matches.map (x) => x.scan @input
      valid: true
        
  '/registry/projects-count': -> @content = @get('../project')?.length
  '/registry/packages-count': -> @content = @get('../package')?.length
  '/registry/sources-count':  -> @content = @get('../source')?.length

  # Registry Actions

  '/registry/sync': ->
    { host, force } = @input
    parse    = @in('/npm:parse')
    projects = @in('/npm:registry/project')
    packages = @in('/npm:registry/package')
    sources  = @in('/npm:registry/source')
    cachedir = @get('/npm:policy/cache/directory')

    isLocal = @schema.lookup('typedef','local-file-dependency').convert

    # recursively discover new packages from registry
    seen = {}
    discover = co.wrap (pkgs...) ->
      pkgs = pkgs.map (pkg) ->
        { name, match } = pkg
        unless force or match is 'latest'
          exists = projects.get(name)
          if exists? and semver.satisfies exists.latest, match
            match += " > #{exists.latest}"
        "#{name}@#{match}"
      pkgs = pkgs.filter (pkg) -> not seen[pkg] and seen[pkg] = true
      debug? "[sync] checking npm registry for #{pkgs}"
      pkgs = yield registry.view pkgs...
      debug? "[sync] match #{pkgs.length} package manifests from npm registry"
      pkgs = yield pkgs.map (pkg) -> parse.do source: pkg
      deps = pkgs.reduce ((a, pkg) ->
        return a unless pkg.dependencies.required?
        a.concat pkg.dependencies.required.filter (x) ->
          try return false if isLocal x.match
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
      debug? "[sync] source merge done"
        
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
      updates = projects.merge(projs, force: true).in('update')
      switch
        when updates? and Array.isArray updates then updates.forEach (f) -> f.do()
        when updates? then updates.do()
      return {
        projects: projs.length
        packages: pkgs.length
        sources: srcs.length
      }

  '/registry/query': ->
    pkgs = @input.package
    pkgs ?= [ @input ]
    @output = co =>
      if @input.sync then yield @in('/npm:registry/sync').do package: pkgs
      matches = []
      for { name, match } in pkgs
        project = @get("/npm:registry/project/#{name}")
        continue unless project? # should throw error?
        match = project.latest if match is 'latest'
        revs = project.release
          .filter (rev) -> semver.satisfies rev.version, match
        continue unless revs.length # should throw error?
        res = switch @input.filter
          when 'earliest' then @get(revs[0].manifest)
          when 'latest'   then @get(revs[revs.length-1].manifest)
          else revs.map (rev) => @get(rev.manifest)
        if @input.filter is 'all'
          debug? "[query] #{name}@#{match} matched #{res.length} releases"
          matches.push res...
        else
          debug? "[query] #{name}@#{match} for #{@input.filter} matched version #{res.version}"
          matches.push res
      package: matches

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
