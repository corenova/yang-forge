# yang-compiler

The **yang-compiler** class provides support for basic set of
YANG schema modeling language by using the built-in *extension* syntax
to define additional schema language constructs.

The compiler only supports bare minium set of YANG statements and
should be used only to generate a new compiler such as 'yang-compiler'
which implements the version 1.0 of the YANG language specifications.

First we declare the compiler class as an extension of the
`Meta` class.  For details on `Meta` please refer to
[Meta class source](http://github.com/saintkepha/data-synth/src/meta.litcoffee).

    Meta = (require 'data-synth').Meta

    class YangCompiler extends Meta
      @set synth: 'compiler'
      
As the compiler encounters various YANG statement extensions, the
`resolver` routines invoked will take different actions, including
`define` of a new meta attribute to be associated with the module as
well as `resolve` to retrieve meta attribute about the module being
compiled (including from external imported modules mapped by prefix).

      define: (type, key, value) ->
        exists = @resolve type, key, false
        switch
          when not exists?
            [ prefix..., key ] = key.split ':'
            base =
              (if prefix.length > 0
                @[prefix[0]] ?= {}
                @[prefix[0]].exports ?= {}
                @[prefix[0]].exports
              else
                @exports ?= {}
                @exports)
            #@set "#{type}.#{key}", value
            Meta.copy base, Meta.objectify "#{type}.#{key}", value
          when Meta.instanceof exists
            exists.merge value
          when exists.constructor is Object
            Meta.copy exists, value
        return undefined

      resolve: (type, key, warn=true) ->
        [ prefix..., key ] = key.split ':'
        base = if prefix.length > 0 then @[prefix[0]]?.exports else @exports
        match = base?[type]?[key]
        if not match? and warn
          console.log "[resolve] unable to find #{type}:#{key}"
        return match

The `parse` function performs recursive parsing of passed in statement
and sub-statements and usually invoked in the context of the
originating `compile` function below.  It expects the `statement` as
an Object containing prf, kw, arg, and any substmts as an array.  It
currently does NOT perform semantic validations but rather simply
ensures syntax correctness and building the JS object tree structure.

      normalize = (obj) -> ([ obj.prf, obj.kw ].filter (e) -> e? and !!e).join ':'

      parse: (input, parser=(require 'yang-parser')) ->
        try
          input = (parser.parse input) if typeof input is 'string'
        catch e then console.error "[parse] failed to parse: #{input}"
          
        console.assert input instanceof Object,
          "must pass in proper input to parse"

        params = 
          (@parse stmt for stmt in input.substmts)
          .filter (e) -> e?
          .reduce ((a, b) -> Meta.copy a, b, true), {}
        params = undefined unless Object.keys(params).length > 0

        unless params?
          Meta.objectify "#{normalize input}", input.arg
        else
          Meta.objectify "#{normalize input}.#{input.arg}", params

The `preprocess` function is the intermediary method of the compiler
which prepares a parsed output to be ready for the `compile`
operation.  It deals with any `include` and `extension` statements
found in the parsed output in order to prepare the context for the
`compile` operation to proceed smoothly.

      preprocess: (input, context) ->
        return @fork (-> @preprocess input, this) unless context?

        input = (@parse input) if typeof input is 'string'
        console.assert input instanceof Object,
          "must pass in proper input to preprocess"

        extractKeys = (x) -> if x instanceof Object then (Object.keys x) else [x].filter (e) -> e? and !!e

        console.log "[preprocess:#{@id}] scanning input schema for 'extension' and 'include' statements"
        context.exports ?= {}
        foundExtensions = []
        for key, val of input when (/^(sub)*module$/.test key) and val instanceof Object
          for arg, params of val when params instanceof Object
            if params.extension?
              params.extension = 
                (extractKeys params.extension)
                .map (name) =>
                  foundExtensions.push name
                  extension = switch
                    when params.extension instanceof Object then params.extension[name]
                    else {}
                  Meta.copy extension, context.get "extensions.#{name}"
                  context.define 'extension', name, extension
                  Meta.objectify name, extension
                .reduce ((a, b) -> Meta.copy a, b), {}
            if params.include?
              unless params.include instanceof Object
                params.include = (Meta.objectify params.include, undefined)
              params.include =
                (@include name, context for name of params.include)
                .reduce ((a, b) -> Meta.copy a, b), {}
            if params.import?
              unless params.import instanceof Object
                params.import = (Meta.objectify params.import, undefined)
              params.import =
                (@import name, opts, context for name, opts of params.import)
                .reduce ((a, b) -> Meta.copy a, b), {}
            
        if foundExtensions.length > 0
          console.log "found #{foundExtensions.length} new extension"+('s' if foundExtensions.length > 1)
          console.log foundExtensions.join ', '
        return input

      path = require 'path'
      fs = require 'fs'

      searchPath: (name) ->
        pkgdir = (@constructor.get 'pkgdir') ? '.'
        return [
          "module:@yang/#{name}"
          "module:#{name}"
          "module:#{path.resolve name}"
          "module:#{path.resolve 'lib', name}"
          "schema:" + path.resolve pkgdir, "yang/#{name}.yang"
          "schema:" + path.resolve pkgdir, "yang/#{name}"
          "schema:" + path.resolve "yang/#{name}.yang"
          "schema:" + path.resolve "yang/#{name}"
          "schema:" + path.resolve "#{name}"
        ].filter (e) -> switch (path.extname name)
          when '.yang' then /^schema/.test e
          else true

      load: (target, context=this) ->
        origin = (@constructor.get 'origin') ? global
        errors = []
        console.log "[load] processing '#{target}'..."
        for loadPath in (context.searchPath target)
          [ type, arg... ] = loadPath.split ':'
          arg = arg.join ':'
          console.log "[load] try '#{loadPath}'..."
          try m = switch type
            when 'module'
              try (origin.require arg) catch e then errors.push e; require arg
            when 'schema'
              @compile (fs.readFileSync arg, 'utf-8'), null, context.exports?.extension
          catch e then errors.push e; continue
          break if m?
        console.assert m?,
          "unable to load (sub)module '#{target}' into compile context:\n" + errors.join "\n"
        return m

      include: (target, context=this) ->
        console.log "[include] loading '#{target}'..."
        m = @load target, context
        name = m.get 'name'
        Meta.copy context, m.extract 'exports'
        console.log "[include] submodule '#{name}' loaded into context" 
        Meta.objectify name, m

      import: (target, opts, context=this) ->
        console.log "[import] loading '#{target}'..."
        m = @load target, context
        name = m.get 'name'
        rev = opts['revision-date']
        if rev? and not (m.get "revision.#{rev}")?
          console.warn "[import] requested #{rev} not availabe in '#{name}'"
          console.log m.get 'revision'
          return
        exts = m.get 'exports.extension'
        for key, val of exts when val.override is true
          delete val.override # don't need this to carry over
          console.log "[import] override '#{key}' extension with deviations"
          context.define 'extension', key, val
        console.log "[import] module '#{name}' loaded into context"
        Meta.objectify opts.prefix ? name, m

The `compile` function is the primary method of the compiler which
takes in YANG schema input and produces JS output representing the
input schema as meta data hierarchy.

It accepts following forms of input:
* YANG schema text string
* function that will return a YANG schema text string
* Object output from `parse`

The compilation process can compile any partials or complete
representation of the schema and recursively compiles the data tree to
return a Meta class object representation (with child bindings) of the
provided input.

      # currently 'id' only used to differentiate separate preprocess/compile
      # processes in debug output
      id = 0
      compile: (input, context, scope) ->
        return unless input?
        
        # First we check if `context` is provided as part of `compile`
        # execution.  This is a special argument which informs whether
        # a brand new `compile` process is being invoked or whether it
        # is being invoked as a sub request.  This is to ensure that
        # proper `fork` and state initialization can take place prior
        # to conducting the actual `compile` operation for the
        # requested `input`.  It also ensures that any symbols being
        # define/resolve from the compiler does not impact any
        # subsequent invocation of the `compile` routine.
        unless context?
          scope ?= (@constructor.get 'exports.extension')
          return @fork ->
            @id = id += 1
            console.log "[compile] forked a new compile context #{@id}"
            for key, value of scope
              Meta.copy value, @get "extensions.#{key}"
              @define 'extension', key, value
            console.log "[compile:#{@id}] job started with following extensions: #{Object.keys(scope ? {})}"
            output = @compile input, this
            # if scope?
            #   for ext of @exports?.extension when ext of scope
            #     console.info "deleting #{ext} from exports"
            #     delete @exports.extension[ext]
            console.log "[compile:#{@id}] job finished"
            output

        input = (input.call this) if input instanceof Function
        input = @preprocess input, context if typeof input is 'string'

        console.assert input instanceof Object,
          "must pass in proper input to compile"

        output = class extends Meta
        output.scope = context

        # Here we go through each of the keys of the input object and
        # validate the extension keywords and resolve these keywords
        # if resolvers are associated with these extension keywords.
        for key, val of input
          [ prf..., kw ] = key.split ':'
          unless not scope? or kw of scope
            throw "invalid '#{kw}' extension found during compile operation"

          if key is 'extension'
            output.set key, val
            continue

          ext = @resolve 'extension', key
          console.assert ext instanceof Object,
            "cannot compile statement with unknown extension '#{key}'"
          constraint = scope?[kw]

          # Here we determine whether there are additional instances
          # of this extension or sub-statements to be proceseed and
          # perform additional recursive statement compilations.

          if val instanceof Object and ext.argument? then for arg, params of val
            stuff = switch
              when params instanceof Function then "{ [native code] }"
              when params? then "{ #{Object.keys(params)} }"
              else ""
            console.log "[compile:#{id}] #{key} #{arg} #{stuff}"
            res = switch key
              when 'extension','include','import' then params
              else @compile params, context, ext
            if not params? and constraint in [ '0..1', '1' ]
              output.set key, arg
            else
              output.set "#{key}.#{arg}", params
            if Meta.instanceof res then res.set 'yang', key
            ext.resolver?.call? output, arg, res
          else
            if constraint? and constraint in [ '0..1', '1' ]
              output.set key, val
            else
              output.set "#{key}.#{val}", undefined
            if ext.argument?
              console.log "[compile:#{id}] #{key} #{val?.slice 0, 50}..."
              ext.resolver?.call? output, val, {}
            else
              console.log "[compile:#{id}] #{key}"
              res = switch
                when val instanceof Object then @compile val, context, ext
                else val
              if Meta.instanceof res then res.set 'yang', key
              ext.resolver?.call? output, key, res

        delete output.scope
        return output

Here we return the new `YangCompiler` class for import and use by
other modules.

    module.exports = YangCompiler
