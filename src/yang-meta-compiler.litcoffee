# yang-meta-compiler

The **yang-meta-compiler** class provides support for basic set of
YANG schema modeling language by using the built-in *extension* syntax
to define additional schema language constructs.

The meta compiler only supports bare minium set of YANG statements and
should be used only to generate a new compiler such as 'yang-compiler'
which implements the version 1.0 of the YANG language specifications.

    class Extension extends (require 'meta-class')
      @set resolver: undefined
      @refine: (params={}) -> @merge params
      @resolve: (target, context) ->
        resolver = @get 'resolver'
        return target unless resolver instanceof Function
        
        # TODO: qualify some internal meta params against passed-in target...
        context ?= target
        params = objectify (target.get 'children')
        resolver.call context, (target.get 'name'), params, target

First we declare the compiler class as an extension of the
`meta-class`.  For details on `meta-class` please refer to
http://github.com/stormstack/meta-class

The primary function of the compiler is to `define` new language
extension statements and to `resolve` the extensions with custom
resolvers.  The `compile` operation uses these definitions to produce
the desired output.

    class YangMetaCompiler extends (require 'meta-class')
      @set map: {}

      @define: (name, params={}) ->
        extension = @get "extension/#{name}"
        unless extension?
          extension = class extends Extension
          @set "extension/#{name}", extension
        extension.refine params
        extension
            
      @resolver: (name, resolver) ->
        [ prefix..., name ] = name?.split? ':'
        m = this
        m = m.get "module/#{prf}" for prf in prefix
        extension = m.get "extension/#{name}"
        if resolver instanceof Function
          extension?.merge? resolver: resolver
        extension ?= Extension
        extension

We utilize the above define/resolver mechanisms to initialize the
built-in supported language extensions, first of all which is the
'extension' statement itself.  This allows any `extension` statement
found in the input schema to define a new `Extension` object for
handling the extension.

      @define 'extension',
        argument: 'extension-name'
        description: '0..1'
        reference: '0..1'
        status: '0..1'
        sub: '0..n' # non YANG 1.0 compliant
        resolver: (name, params) -> @define name, params

      @define 'argument', 'yin-element': '0..1'

The `include` extension is also a built-in to the `yang-meta-compiler`
and invoked during `preprocess` operation to pull-in the included
submodule schema as part of the preprocessing output.  It always
expects a local file source which differs from more robust `import`
extension.  The `yang-meta-compiler` does not natively provide any
`import` facilities.

      @map = (obj) -> @merge 'map', obj

      @define 'include',
        argument: 'module'
        resolver: (name, params) ->
          @mixin @preprocess ->
            path = require 'path'
            resolveFile = (filename) -> switch
              when path.isAbsolute filename then filename
              else path.resolve (path.dirname module.parent?.filename), filename
            (require 'fs').readFileSync (resolveFile (@get "map.#{name}")), 'utf-8'
          
## pre-processing schema

The `preprocess` function is the initial primary method of the
compiler which takes in YANG text schema input and produces JS output
representing the input schema as meta data hierarchy.

      @preprocess: (schema, parser=(require 'yang-parser')) ->
        schema = switch
          when typeof schema is 'string' then schema
          when schema instanceof Function then schema.call this
        return unless schema?

The internal `processStatement` function performs recursive compilation of
passed in statement and sub-statements and invoked within the cotext
of the originating `compile` function above.  It expects the
`statement` as an Object containing prf, kw, arg, and any substmts as
an array.

        processStatement = (statement) ->
          return unless statement? and statement instanceof Object

          normalize = (statement) -> ([ statement.prf, statement.kw ].filter (e) -> e? and !!e).join ':'
          keyword = normalize statement

          results = (processStatement stmt for stmt in statement.substmts).filter (e) -> e?
          class extends (require 'meta-class')
            @set yang: keyword, name: statement.arg, children: results 

The output of `processStatement` is then traversed to handle the
**built-in** extensions resolution (such as include).

        processStatement (parser.parse schema)
        .mixin this
        .traverse (parent, origin) -> (origin.resolver (@get 'yang')).resolve this, origin
        
## compiling pre-processed output

      @compile: (func) ->
        func?.call? this
        @traverse (parent, origin) -> (origin.resolver (@get 'yang')).resolve this, origin

Here we return the new `YangMetaCompiler` class for import and use by other
modules.

    module.exports = YangMetaCompiler

