require 'yang-js'
debug = require('debug')('yang-forge:npm') if process.env.DEBUG?
co = require 'co'
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

  'grouping(packages-list)/package/scan': ->
    { name, version, dependencies } = pkg = @get('..')
    return @output = pkg.scanning if pkg.scanning? and not @input.force
    @output = pkg.scanning = co =>
      start = new Date
      unless pkg.scanned
        main = path.normalize pkg.main.source
        debug? "[scan(#{name}@#{version})] using '#{main}' from #{pkg.source}"
        archive = @get(pkg.source)
        yield archive.tag files: [ 'package.json' ]
        main = yield archive.resolve main
        yield main.scan tag: true

        # TODO: may be a single match? (should be atleast 2 in all cases...)
        seen = {}
        deps = archive.$("file[scanned = true()]/imports")?.filter (x) -> x?
        deps = [].concat(deps...).filter (x) -> not seen[x] and seen[x] = true
        debug? "[scan(#{name}@#{version})] found #{deps.length} pkg dependencies: #{deps}" if deps.length
        missing = []
        for dep in deps when dep not of process.binding('natives')
          # TODO: deal with dep like 'foo/bar' (flag warning?)
          d = dependencies.$("required/#{dep}")
          if d? then d.used = true else missing.push dep
        dependencies.missing = missing
        pkg.scanned = true

      debug? "[scan(#{name}@#{version})] discovering required dependencies"
      requires = dependencies.$("required[used = true()]")
      return valid: true, dependency: [] unless requires?

      requires = [ requires ] unless Array.isArray requires
      res = yield @in('/registry/query').do
        package: requires
        filter: 'latest'
        sync: false

      requires = {}
      for dependency in res.package
        key = dependency['@key']
        # scan this dependency
        unless key of requires
          res = yield @get("/npm:registry/package/#{key}").scan()
          for subdep in res.dependency
            subkey = subdep['@key']
            requires[subkey] ?= []
            requires[subkey].push subdep.dependents...
        requires[key] ?= []
        requires[key].push name
        # requires[key] = [ name ]
          
      requires = (
        for k, v of requires
          [ n, ver ] = k.split('+')
          name: n
          version: ver
          dependents: v
      )
      debug? "[scan(#{name}@#{version})] requires #{requires.length} dependencies: #{requires.map (x) -> x.name}"
      debug? "[scan(#{name}@#{version})] took #{(new Date - start)/1000} seconds"
      valid: true
      dependency: requires

  'grouping(packages-list)/package/extract': ->
    { dest, dependencies } = @input
    pkg = @get('..')
    @output = co =>
      debug? "[extract(#{pkg.name}@#{pkg.version})] using #{pkg.source}"
      scanned = yield pkg.scan()
      archive = @get(pkg.source)
      extracted = yield archive.extract dest: dest, filter: { tagged: true }
      if dependencies
        debug? "[extract(#{pkg.name}@#{pkg.version})] unpacking #{scanned.dependency.length} dependencies"
        dest = path.join dest, 'node_modules'
        deps = yield scanned.dependency.map (dep) =>
          debug? "[extract(#{pkg.name}@#{pkg.version})] unpacking #{dep.name} #{dep.version}"
          depkg = @get("/npm:registry/package/#{dep.name}+#{dep.version}")
          depkg.$('extract',true).do dependencies: false, dest: path.join dest, dep.name
      name: pkg.name
      version: pkg.version
      files: extracted.files
      module: deps ? []
    
  'grouping(packages-list)/package/serialize': ->
    manifest = @parent.toJSON(false)
    # TODO need to convert back to package.json format

  'grouping(source-archive)/resolve': (name) ->
    files = @in('../file')
    # TODO: handle case where 'name' is pointing at a directory with package.json
    for check in [ name, name+'.js', path.join(name,'index.js') ]
      match = files.get(".[name = '#{check}']")
      break if match?
    @output = match

  'grouping(source-archive)/file/scan': ->
    { tag } = @input
    archive = @get('../../..')
    entry = @get('..')
    basedir = path.join entry.name, '..'
    isLocal = @schema.lookup('typedef','local-file-dependency').convert
    
    @output = co =>
      return valid: true if entry.scanned
      file = yield entry.read()
      seen = {}
      debug? "[scan(#{entry.name})] detecting dependencies"
      try requires = detect(file.data).filter (x) -> not seen[x] and seen[x] = true
      catch e then @throw "unable to detect dependencies on #{entry.name}"
        
      debug? "[scan(#{entry.name})] requires: #{requires}" if requires?.length
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
    stables = @get('../release[stable = true()]')
    return unless stables?
    @content = switch
      when Array.isArray(stables) then stables[stables.length-1].version
      else stables.version
  '/registry/project/created-on': ->
    @content ?= @get('../release[1]').timestamp
  '/registry/project/modified-on': ->
    releases = @get('../release')
    @content = releases[releases.length-1].timestamp
  '/registry/project/releases-count': ->
    @content = @get('../release').length
  '/registry/project/release/stable': ->
    version = @get('../version')
    @content ?= version.indexOf('-') is -1
  '/registry/project/release/manifest': ->
    name = @get('../../../name')
    version = @get('../version')
    unless @content?
      match = @in("/npm:registry/package/#{name}+#{version}")
      @content = "#{match.path}" if match?

  '/registry/package/published-on': ->
    { name, version } = @get('..')
    @content ?= @get("/npm:registry/project/#{name}/release/#{version}/timestamp")

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
    checked = {}
    fetched = {}
    discover = co.wrap (pkgs...) ->
      pkgs = pkgs.map (pkg) ->
        { name, match } = pkg
        unless force or match is 'latest'
          exists = projects.get(name)
          if exists? and semver.satisfies(exists.latest, match)
            unless semver.valid(match)
              match += " > #{exists.latest}"
            else
              checked["#{name}@#{match}"] = true
        "#{name}@#{match}"
      pkgs = pkgs.filter (pkg) -> not checked[pkg] and checked[pkg] = true
      debug? "[sync] checking npm registry for #{pkgs}"
      pkgs = yield registry.view pkgs...
      pkgs = pkgs.filter (pkg) ->
        key = "#{pkg.name}@#{pkg.version}"
        not fetched[key] and fetched[key] = true
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
      start = new Date
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
      updates = projects.merge(projs, force: true).in('update')
      switch
        when updates? and Array.isArray updates then updates.forEach (f) -> f.do()
        when updates? then updates.do()
      console.log "[sync] took #{((new Date) - start)/1000} seconds"
      return {
        projects: projs.length
        packages: pkgs.length
        sources: srcs.length
      }

  '/registry/query': ->
    debug? "[query] enter with sync: #{@input.sync}"
    pkgs = @input.package ? [ @input ]
    @output = co =>
      start = new Date
      if @input.sync then yield @in('/npm:registry/sync').do package: pkgs
      matches = []
      for { name, match } in pkgs
        project = @get("/npm:registry/project/#{name}")
        continue unless project? # should throw error?
        match = project.latest if match is 'latest'
        revs = project.$('release[stable = true()]')
        continue unless revs?
        revs = [ revs ] unless Array.isArray revs
        revs = revs.filter (rev) -> semver.satisfies rev.version, match
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
      debug? "[query] took #{(new Date - start)/1000} seconds"
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

  install: ->
    @output = co =>
      start = new Date
      res = yield @in('/npm:registry/query').do @input
      yield res.package.map (pkg) =>
        pkg = @get("/npm:registry/package/#{pkg.name}+#{pkg.version}")
        pkg.extract @input
      console.log "[install] took #{(new Date - start)/1000} seconds"
}
