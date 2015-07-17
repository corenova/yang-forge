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

    assert = require 'assert'
    Meta = (require 'data-synth').Meta

    class YangCompiler extends Meta
      @mixin (require './compiler-mixin')

As the compiler encounters various YANG statement extensions, the
`resolver` routines invoked will take different actions, including
`define` of a new meta attribute to be associated with the module as
well as `resolve` to retrieve meta attribute about the module being
compiled (including from external imported modules mapped by prefix).

      define: (type, key, value) ->
        exists = @resolve type, key
        unless exists?
          #@set "#{type}.#{key}", value
          @exports ?= {}
          Meta.copy @exports, Meta.objectify "#{type}.#{key}", value
        undefined

      resolve: (type, key) ->
        [ prefix..., key ] = key.split ':'
        switch
          when prefix.length > 0
            (@resolve 'module', prefix[0])?.get "#{type}.#{key}"
          else
            #@get "#{type}.#{key}"
            @exports?[type]?[key]

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
        catch e then console.log "ERR: [parse] failed to parse: #{input}"
          
        assert input instanceof Object,
          "must pass in proper input to parse"

        params = 
          (@parse stmt for stmt in input.substmts)
          .filter (e) -> e?
          .reduce ((a, b) -> Meta.copy a, b), {}
        params = undefined unless Object.keys(params).length > 0

        # the below distinction checking for '.' is a hack...
        if ~input.arg.indexOf '.'
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
        assert input instanceof Object,
          "must pass in proper input to preprocess"

        extractKeys = (x) -> if x instanceof Object then (Object.keys x) else [x].filter (e) -> e? and !!e

        console.log "INFO: [preprocess:#{@id}] scanning input for 'extension' and 'include' statements"
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
              params.include = 
                (extractKeys params.include)
                .map (name) =>
                  console.log "INFO: [preprocess:#{@id}:include] submodule '#{name}'"
                  submod = (require name)
                  console.log "INFO: [preprocess:#{@id}:include] submodule '#{name}' loaded: #{submod?}"
                  # grab export data from submodule and include into context
                  # a bit hackish ATM...
                  Meta.copy context, submod?.extract 'exports'
                  Meta.objectify name, submod
                .reduce ((a, b) -> Meta.copy a, b), {}
        console.log "INFO: [preprocess:#{@id}] found extensions: '#{foundExtensions}'"
        return input

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
          return @fork ->
            @id = id += 1
            console.log "INFO: [compile] forked a new compile context #{@id}"
            obj = @constructor.get 'exports.extension'
            for key, value of obj
              Meta.copy value, @get "extensions.#{key}"
              @define 'extension', key, value
            console.log "INFO: [compile:#{@id}] job started with following extensions: #{Object.keys(obj ? {})}"
            output = @compile input, this
            output?.merge 'exports', @exports
            console.log "INFO: [compile:#{@id}] job finished"
            output

        input = (input.call this) if input instanceof Function
        input = @preprocess input, context if typeof input is 'string'

        assert input instanceof Object,
          "must pass in proper input to compile"

        output = class extends Meta
        output.compiler = context

        # Here we go through each of the keys of the input object and
        # validate the extension keywords and resolve these keywords
        # if resolvers are associated with these extension keywords.
        #
        # TODO: need to also assert on cardinality of each
        # sub-statements
        for key, val of input when not scope? or key of scope
          if key is 'extension'
            output.set key, val
            continue

          ext = @resolve 'extension', key
          assert ext instanceof Object,
            "ERROR: cannot compile statement with unknown extension '#{key}'"

          # Here we determine whether there are additional instances
          # of this extension or sub-statements to be proceseed and
          # perform additional recursive statement compilations.

          if val instanceof Object and ext.argument? then for arg, params of val
            stuff = switch
              when params instanceof Function then "{ [native code] }"
              when params? then "{ #{Object.keys(params)} }"
              else ""
            console.log "INFO: [compile:#{id}] #{key} #{arg} #{stuff}"
            res = switch key
              when 'extension','include' then params
              else @compile params, context, ext
            output.set "#{key}.#{arg}", params
            ext.resolver?.call? output, arg, res
          else
            output.set key, val
            if ext.argument?
              console.log "INFO: [compile:#{id}] #{key} #{val.slice 0, 50}..."
              ext.resolver?.call? output, val, {}
            else
              console.log "INFO: [compile:#{id}] #{key}"
              ext.resolver?.call? output, key, val

        delete output.compiler
        return output

Here we return the new `YangCompiler` class for import and use by
other modules.

    module.exports = YangCompiler
