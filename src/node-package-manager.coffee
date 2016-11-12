require 'yang-js'
debug = require('debug')('yang-forge:npm') if process.env.DEBUG?

registry = require './npm-registry'
cache = {}

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

  'grouping(packages-list)/package/serialize': ->
    manifest = @parent.toJSON(false)

  '/specification': ->
    @content ?=
      keywords: [
        'name', 'version', 'license', 'description', 'homepage', 'bugs', 'repository', 'config'
        'main', 'author', 'keywords', 'maintainers', 'contributors', 'dist', 'versions', 'time'
        'dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies', 'bundleDependencies'
        'main', 'files', 'directories', 'scripts', 'bin', 'engines'
        'os', 'cpu', 'preferGlobal', 'private', 'publishConfig'
      ]

  '/registry': -> @content ?= package: []
  
  transform: ->
    src = switch typeof @input.source
      when 'string' then JSON.parse @input.source
      else @input.source

    # bypass transform if already matches schema
    match = @get("/registry/package/#{src.name}+#{src.version}")
    return (@output = match) if match?
    return (@output = src) if src.policy?

    debug? "transforming '#{src.name}' package into package-manifest data model"

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
      revision:    src.versions?.map (ver) ->
        version:   ver
        timestamp: src.time[ver] ? src.time[ver.replace('-','')]
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

  query: ->
    store = @in('/registry/package')
    cached = []
    pkgs = @input.package.reduce ((a,pkg) ->
      hit = store.get("#{pkg.name}+#{pkg.source}")
      if hit? then cached.push hit
      else a.push if pkg.source? then "#{pkg.name}@#{pkg.source}" else pkg.name
      return a
    ), []
    debug? "[query] found #{cached.length} cached entries" if cached.length
    return @output = package: cached unless pkgs.length
    debug? "[query] checking npm registry for #{pkgs}"
    transformer = @in('/transform')
    @output =
      registry.view pkgs...
      .then (res) ->
        Promise.all res.map (x) -> transformer.do source: x
      .then (res) ->
        debug? "merging #{res.length} packages into internal registry"
        store.merge res, force: true
        package: cached.concat res
        
}
