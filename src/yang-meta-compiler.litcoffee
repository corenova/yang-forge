# yang-meta-compiler

The **yang-meta-compiler** class provides support for basic set of
YANG schema modeling language by using the built-in *extension* syntax
to define additional schema language constructs.

The meta compiler only supports bare minium set of YANG statements and
should be used only to generate a new compiler such as 'yang-compiler'
which implements the version 1.0 of the YANG language specifications.

    Meta = require 'meta-class'

First we declare the compiler class as an extension of the
`meta-class`.  For details on `meta-class` please refer to
http://github.com/stormstack/meta-class

    class YangMetaCompiler extends Meta

      assert = require 'assert'

As the compiler encounters various YANG statement extensions, the
`resolver` routines invoked will take different actions, including
`define` of a new meta attribute to be associated with the module as
well as `resolve` to retrieve meta attribute about the module being
compiled (including from external imported modules mapped by prefix).

      define: (type, key, value) ->
        exists = @resolve type, key
        unless exists?
          @context ?= {}
          Meta.copy @context, Meta.objectify "#{type}.#{key}", value
        undefined

      resolve: (type, key) ->
        [ prefix..., key ] = key.split ':'
        switch
          when prefix.length > 0
            (@resolve 'module', prefix[0])?.get "#{type}.#{key}"
          else
            @context?[type]?[key]

The `parse` function performs recursive parsing of passed in statement
and sub-statements and usually invoked in the context of the
originating `compile` function below.  It expects the `statement` as
an Object containing prf, kw, arg, and any substmts as an array.

      parse: (schema, context, parser=(require 'yang-parser')) ->
        return @fork (-> @parse schema, this) unless context?

        if typeof schema is 'string'
          return @parse (parser.parse schema), context

        assert schema instanceof Object,
          "must pass in proper input to parse"

        statement = schema
        normalize = (obj) -> ([ obj.prf, obj.kw ].filter (e) -> e? and !!e).join ':'
        keyword = normalize statement

        params = 
          (@parse stmt, kw: keyword for stmt in statement.substmts)
          .filter (e) -> e?
          .reduce ((a, b) -> Meta.copy a, b), {}

        if keyword is 'include' and /^(sub)*module$/.test context.kw
          source = @get "map.#{statement.arg}"
          assert typeof source is 'string',
            "unable to include '#{statement.arg}' without mapping defined for source"
          path = require 'path'
          file = path.resolve (path.dirname module.parent?.filename), source
          console.log "INFO: including '#{statement.arg}' using #{file}"
          schema = (require 'fs').readFileSync file, 'utf-8'
          res = @parse schema, context
          sub = res?.submodule?[statement.arg]
          # TODO: qualify belongs-to
          return sub

        if keyword is 'extension' and /^(sub)*module$/.test context.kw
          params.resolver = @get "extensions.#{statement.arg}"
          @define 'extension', statement.arg, params

        switch
          when Object.keys(params).length > 0
            Meta.objectify "#{keyword}.#{statement.arg}", params
          else
            Meta.objectify keyword, statement.arg

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

      compile: (input, context) ->

First we check if `context` is provided as part of `compile`
execution.  This is a special argument which informs whether a brand
new `compile` process is being invoked or whether it is being invoked
as a sub request.  This is to ensure that proper `fork` and state
initialization can take place prior to conducting the actual `compile`
operation for the requested `input`.  It also ensures that any symbols
being define/resolve from the compiler does not impact any subsequent
invocation of the `compile` routine.
        
        unless context?
          return @fork ->
            obj = @constructor.extract 'extension'
            for key, value of obj.extension
              override = @get "extensions.#{key}"
              value.resolver = override if override?
              @define 'extension', key, value
            @compile input, this

        input = (input.call this) if input instanceof Function
        input = @parse input, context if typeof input is 'string'

        assert input instanceof Object,
          "must pass in proper input to compile"

        output = class extends Meta
        output.compiler = this

        validSubs = context?.extension?.sub

Here we go through each of the keys of the input object and validate
the extension keywords and resolve these keywords if resolvers are
associated with these extension keywords.

TODO: need to also assert on cardinality of each sub-statements

        for key, val of input when not validSubs? or key of validSubs
          if key is 'extension'
            output.set key, val
            continue

          ext = @resolve 'extension', key
          assert ext instanceof Object,
            "ERROR: cannot compile statement with unknown extension '#{key}'"

Here we determine whether there are additional instances of this
extension or sub-statements to be proceseed and perform additional
recursive statement compilations.

          if val instanceof Object and ext.argument? then for arg, params of val
            #console.log "INFO: compiling #{key}.#{arg} with: #{Object.keys(params)}"
            res = @compile params, key: "#{key}.#{arg}", extension: ext
            output.set "#{key}.#{arg}", params
            ext.resolver?.call? output, arg, res
          else
            #console.log "INFO: compiling #{key}"
            output.set key, val
            if ext.argument?
              ext.resolver?.call? output, val, {}
            else
              ext.resolver?.call? output, key, val

        delete output.compiler
        output

Here we return the new `YangMetaCompiler` class for import and use by
other modules.

    module.exports = YangMetaCompiler
