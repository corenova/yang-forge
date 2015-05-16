# yang-meta-compiler

The **yang-meta-compiler** class provides support for basic set of
YANG schema modeling language by using the built-in *extension* syntax
to define additional schema language constructs.

The meta compiler only supports bare minium set of YANG statements and
should be used only to generate a new compiler such as 'yang-compiler'
which implements the version 1.0 of the YANG language specifications.

    Meta = require 'meta-class'

    class Extension
      constructor: (@params={}) -> this
      refine: (params={}) -> Meta.copy @params, params
      resolve: (target, compiler) ->
        # TODO should ignore 'date'
        # Also this bypass logic should also be based on whether sub-statements are allowed or not
        switch @params.argument
          when 'value','text','date'
            return name: (target.get 'yang'), value: (target.get 'name')

        unless @params.resolver?
          throw new Error "no resolver found for '#{target.get 'yang'}' extension", target

        arg = (target.get 'name').replace ':','.'
        # do something if arg has prefix:something

        
        # TODO: qualify some internal meta params against passed-in target...
        params = {}
        (target.get 'children')?.forEach (e) ->
          switch
            when (Meta.instanceof e) and (e.get 'children').length is 0
              params[e.get 'yang'] = e.get 'name'
            when e?.constructor is Object
              params[e.name] = e.value
        @params.resolver?.call? compiler, target, arg, params

First we declare the compiler class as an extension of the
`meta-class`.  For details on `meta-class` please refer to
http://github.com/stormstack/meta-class

    class YangMetaCompiler extends Meta

      assert = require 'assert'

      @set extensions:
      
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
            ext = @get "extensions.#{arg}"
            unless ext?
              params.resolver ?= @get "resolvers.#{arg}"
              ext = new Extension params
              @set "extensions.#{arg}", ext
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
            assert typeof source is 'string', "unable to include '#{arg}' without mapping defined for source"
            @compile ->
              path = require 'path'
              file = path.resolve (path.dirname module.parent?.filename), source
              console.log "INFO: including '#{arg}' using #{file}"
              (require 'fs').readFileSync file, 'utf-8'

One of the key function of the compiler is to `resolve` language
extension statements with custom resolvers given the meta class input.
The `compile` operation uses the `resolve` definitions to produce the
desired output.

      resolver: (meta, context) ->
        yang = meta.get 'yang'
        [ prefix..., yang ] = (yang.split ':' ) if typeof yang is 'string'
        ext = switch
          when prefix.length > 0 then (@get "#{prefix[0]}")?.get "extensions.#{yang}"
          else @get "extensions.#{yang}"

        try ext.resolve meta, this
        catch err
          @errors ?= []
          @errors.push
            yang: yang
            error: err
          undefined

The below `assembler` performs the task of combining the source object
into the destination object by creating a binding between the two.
This allows the source object to be auto constructed when the
destination object is created.  This is a helper routine used during
compilation as part of reduce traversal.

      assembler: (dest, src) ->
        objs = switch
          when src.collapse is true
            name: k, value: v for k, v of (src.get 'bindings')
          when (Meta.instanceof src)
            name: @normalizeKey src
            value: src
          when src.constructor is Object
            src
        objs = [ objs ] unless objs instanceof Array
        Meta.bind.apply dest, objs
        
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
          @set 'extensions', @constructor.get 'extensions'
        
          # refine existing resolvers if new ones supplied during instantiation
          for name, ext of (@get 'extensions') when (@get "resolvers.#{name}") instanceof Function
            ext.refine resolver: @get "resolvers.#{name}"

          output =
            @parse schema
            .map    => @resolver.apply this, arguments
            .reduce => @assembler.apply this, arguments
            
          if @errors?
            console.log "WARN: the following errors were encountered by the compiler"
            console.log @errors
            
          self = this
          output.configure ->
            @set "schema", schema
            @merge self.extract 'map', 'extensions', 'exports'

Here we return the new `YangMetaCompiler` class for import and use by
other modules.

    module.exports = YangMetaCompiler
