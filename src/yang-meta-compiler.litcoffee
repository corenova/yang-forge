# yang-meta-compiler

The **yang-meta-compiler** class provides support for basic set of
YANG schema modeling language by using the built-in *extension* syntax
to define additional schema language constructs.

The meta compiler only supports bare minium set of YANG statements and
should be used only to generate a new compiler such as 'yang-compiler'
which implements the version 1.0 of the YANG language specifications.

    Meta = require 'meta-class'

    class Extension
      constructor: (@opts={}) -> this
      refine: (opts={}) -> Meta.copy @opts, opts
      resolve: (target, compiler) ->
        # TODO should ignore 'date'
        # Also this bypass logic should also be based on whether sub-statements are allowed or not
        switch @opts.argument
          when 'value','text','date'
            return name: (target.get 'yang'), value: (target.get 'name')

        unless @opts.resolver?
          throw new Error "no resolver found for '#{target.get 'yang'}' extension", target

        arg = (target.get 'name')
        
        # TODO: qualify some internal meta params against passed-in target...
        params = {}
        (target.get 'children')?.forEach (e) ->
          switch
            when (Meta.instanceof e) and (e.get 'children').length is 0
              params[e.get 'yang'] = e.get 'name'
            when e?.constructor is Object
              params[e.name] = e.value
        @opts.resolver?.call? compiler, target, arg, params

First we declare the compiler class as an extension of the
`meta-class`.  For details on `meta-class` please refer to
http://github.com/stormstack/meta-class

    class YangMetaCompiler extends Meta

      assert = require 'assert'

      @set 'exports.yang',
      
We configure meta data of the compiler to initialize the built-in
supported language extensions, first of which is the 'extension'
statement itself.  This allows any `extension` statement found in the
input schema to define a new `Extension` object for handling the
extension by the compiler.
      
        extension: new Extension
          argument: 'extension-name'
          'sub:description': '0..1'
          'sub:reference': '0..1'
          'sub:status': '0..1'
          'sub:sub': '0..n'
          resolver: (self, arg, params) ->
            ext = @resolve 'yang', arg
            unless ext?
              params.resolver ?= @get "extensions.#{arg}"
              ext = new Extension params
              @define 'yang', arg, ext
            else
              ext.refine params
            ext

The following set of built-in Extensions are statements used in
defining the extension itself.

        argument: new Extension
          'sub:yin-element': '0..1'
          resolver: (self, arg) -> name: 'argument', value: arg
          
        'yin-element': new Extension argument: 'value'

        value:  new Extension resolver: (self, arg) -> name: 'value', value: arg
        sub:    new Extension resolver: (self, arg, params) -> name: "sub:#{arg}", value: params
        prefix: new Extension argument: 'value'

The `include` extension is also a built-in to the `yang-meta-compiler`
and invoked during `compile` operation to pull-in the included
submodule schema as part of the preprocessing output.  It always
expects a local file source which differs from more robust `import`
extension.  The `yang-meta-compiler` does not natively provide any
`import` facilities.

        include: new Extension
          argument: 'name'
          resolver: (self, arg, params) ->
            source = @get "map.#{arg}"
            assert typeof source is 'string',
              "unable to include '#{arg}' without mapping defined for source"
            @compile ->
              path = require 'path'
              file = path.resolve (path.dirname module.parent?.filename), source
              console.log "INFO: including '#{arg}' using #{file}"
              (require 'fs').readFileSync file, 'utf-8'

As the compiler encounters various YANG statement extensions, the
`resolver` routines invoked will take different actions, including
`define` of a new meta attribute to be associated with the module as
well as `resolve` to retrieve meta attribute about the module being
compiled (including from external imported modules mapped by prefix).

      define: (type, key, value) ->
        exists = @resolve type, key
        unless exists?
          @context[type] ?= {}
          @context[type][key] = value
        undefined

      resolve: (type, key) ->
        [ prefix..., key ] = key.split ':'
        from = switch
          when prefix.length > 0 then (@resolve 'module', prefix[0])?.get 'exports'
          else @context
        from?[type]?[key]

One of the key function of the compiler is to `resolve` language
extension statements with custom resolvers given the meta class input.
The `compile` operation uses the `resolve` definitions to produce the
desired output.

      resolveNode: (meta) ->
        yang = meta.get 'yang'
        ext = (@resolve 'yang', yang)
        try ext.resolve meta, this
        catch err
          @errors ?= []
          @errors.push
            yang: yang
            error: err
          undefined

The below `assembler` performs the task of combining the 'from' object
into the 'to' object by creating a binding between the two.  This
allows the source object to be auto constructed when the destination
object is created.  This is a helper routine used during compilation
as part of reduce traversal.

      assembleNode: (to, from) ->
        objs = switch
          when (Meta.instanceof from)
            if (from.get 'collapse')
              name: k, value: v for k, v of (from.get 'bindings')
            else
              name: @normalizeKey from
              value: from
          when from.constructor is Object
            from
        objs = [ objs ] unless objs instanceof Array
        Meta.bind.apply to, objs
        
      normalizeKey: (meta) ->
        ([ (meta.get 'yang'), (meta.get 'name') ].filter (e) -> e? and !!e).join '.'

The `parse` function performs recursive parsing of passed in statement
and sub-statements and usually invoked in the context of the
originating `compile` function below.  It expects the `statement` as
an Object containing prf, kw, arg, and any substmts as an array.

      parse: (schema, parser=(require 'yang-parser')) ->
        if typeof schema is 'string'
          return @parse (parser.parse schema)

        return unless schema? and schema instanceof Object

        statement = schema
        normalize = (obj) -> ([ obj.prf, obj.kw ].filter (e) -> e? and !!e).join ':'
        keyword = normalize statement

        results = (@parse stmt for stmt in statement.substmts).filter (e) -> e?
        class extends (require 'meta-class')
          @set yang: keyword, name: statement.arg, children: results

The `compile` function is the primary method of the compiler which
takes in YANG text schema input and produces JS output representing
the input schema as meta data hierarchy.

It accepts two forms of input: a YANG schema text string or a function
that will return a YANG schema text string.

      compile: (schema) ->
        schema = (schema.call this) if schema instanceof Function
        return unless typeof schema is 'string'

The `fork` operation below performs the actual compile logic within
the context of a **child** compiler instance, which is discarded
unless it is returned as an output of the `fork` operation.  This is
to ensure that any `get/set` operations do not impact the primary
compiler instance.

        @fork ->
          @context = yang: @constructor.get 'exports.yang'
        
          # refine existing extensions if new ones supplied during instantiation
          for name, ext of @context.yang when (@get "extensions.#{name}") instanceof Function
            ext.refine resolver: @get "extensions.#{name}"

          output =
            @parse schema
            .map    => @resolveNode.apply this, arguments
            .reduce => @assembleNode.apply this, arguments
            .set schema: schema, exports: @context, 'compiled-using': @get()

          if @errors?
            console.log "WARN: the following errors were encountered by the compiler"
            console.log @errors

          return output

Here we return the new `YangMetaCompiler` class for import and use by
other modules.

    module.exports = YangMetaCompiler
