YangCompiler = require 'yang-compiler'

class YangForge extends YangCompiler
  @set extensions: {}, methods: {}
  
  @extension: (name, func) -> @set "extensions.#{name}.resolver", func
  @action: (name, func) -> @set "methods.#{name}", func

  path = require 'path'
  fs = require 'fs'

  # this is a factory that instantiates based on compiled output of
  # constructor's meta data
  #
  # when called without a 'new' keyword, it creates a forgery of its
  # own class definition representing the blueprint for the new module
  constructor: (input, func) ->
    if @constructor is Object
      assert input instanceof (require 'module'),
        "must pass in 'module' when forging a new module definition, i.e. forge(module)"

      # this is a special hack to ensure that while YangForge itself
      # is being constructed/compiled, other dependent modules needed
      # for YangForge construction itself (such as yang-v1-extensions)
      # can properly export themselves.
      module.exports = YangForge unless module.loaded is true

      console.log "INFO: [forge] processing #{input.id}..."
      try
        pkgdir = path.dirname input.filename
        config = require (path.resolve pkgdir, './package.json')
        unless config.schema instanceof Object
          config.schema =
            path: config.schema
            source: fs.readFileSync (path.resolve pkgdir, config.schema), 'utf-8'
            #source: fs.readFileSync (path.resolve pkgpath, config.schema), 'utf-8'
      catch err
        console.log "Unable to discover YANG schema for the target module, missing 'schema' in package.json?"
        throw err

      console.log "INFO: [forge] forging #{config.name} (#{config.version}) using schema from #{config.schema.path}"
      forgery = class extends YangForge
        @merge config
        @configure func

      compiler = new YangCompiler (forgery.extract 'dependencies', 'extensions', 'methods')
      output = compiler.compile forgery.get 'schema.source'
      return forgery.merge output
      
    super
    
module.exports = YangForge module, ->
  @action 'import', (input) -> @import input
