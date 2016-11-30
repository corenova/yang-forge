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
  '/registry/project/release/package': ->
    name = @get('../../../name')
    version = @get('../version')
    unless @content?
      match = @in("/npm:registry/package/#{name}+#{version}")
      @content = "#{match.path}" if match?
  '/registry/project/release/source': ->
    pkgpath = @get('../package')
    return unless pkgpath?
    srcid = @get("#{pkgpath}/dist/shasum")
    match = @in("/npm:registry/source/#{srcid}")
    @content = "#{match.path}" if match?

  '/registry/source': ->
    unless @content?
      debug? "[#{@path}] update"
      cachedir = @get('/npm:policy/cache/directory')
      keys = @get('/npm:registry/package/dist/shasum')
      return unless keys?
      keys = [ keys ] unless Array.isArray keys
      @content = keys.map (x) -> id: x
  '/registry/source/files-count': ->
    @content ?= @get('../file')?.length
  '/registry/source/files-size': ->
    @content ?= @get('../file')?.reduce ((size, i) -> size += i.size), 0

  '/registry/source/file/load': ->
    files = @in('../../../file')
    cachedir = @get('/npm:policy/cache/directory')
    srcdir   = @get('../../../id')
    filename = @get('../name')
    cacheloc = path.resolve cachedir, srcdir, filename
    basedir  = path.join filename, '..'

    isLocal = @schema.lookup('typedef','local-file-dependency').convert
    resolveDependency = (dep) ->
      debug? "[load:resolve] resolving #{dep} for #{filename}"
      local = try isLocal dep catch then false
      id: dep
      ref: switch
        when not local
          unless dep of process.binding('natives')
            # TODO: need to handle dep = foo/bar
            "/npm:registry/project/#{dep}"
        else
          dep = path.join basedir, dep
          for check in [ dep, dep+'.js', path.join(dep,'index.js') ]
            match = files.in(".[name = '#{check}']")
            break if match?
          "#{match.path}" if match?

    @output ?= co =>
      debug? "[load] #{filename}"
      try
        src = yield fs.readFile cacheloc, 'utf-8'
        return text: src unless path.extname(filename) in [ '.js', '.node' ]
        seen = {}
        requires = detect(src).filter (x) -> not seen[x] and seen[x] = true
        debug? "[load] #{filename} requires #{requires}"
        return text: src, require: requires.map resolveDependency
      catch e then return text: src, error: e

  '/registry/projects-count': -> @content = @get('../project')?.length
  '/registry/packages-count': -> @content = @get('../package')?.length
  '/registry/sources-count':  -> @content = @get('../source')?.length

  '/policy': -> @content ?= cache: {}
  
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

  sync: ->
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

  query: ->
    { name, source } = @input
    packages = @in('/npm:registry/package')
    @output =
      @in('/npm:sync').do package: [ @input ]
      .then =>
        project = @get("/npm:registry/project/#{name}")
        source = project.latest if source is 'latest'
        project.release
          .filter (rev) -> semver.satisfies rev.version, source
          .map (rev) => @get(rev.package)
      .then (res) -> package: res
      
}
