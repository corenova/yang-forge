# yang-meta-compiler

The **yang-meta-compiler** class provides support for basic set of
YANG schema modeling language by using the built-in *extension* syntax
to define additional schema language constructs.

The meta compiler only supports bare minium set of YANG statements and
should be used only to generate a new compiler such as 'yang-compiler'
which implements the version 1.0 of the YANG language specifications.

    class Extension
      constructor: (@name, @params) -> this
      
      #@set resolver: undefined #(arg, params) -> o = {}; o[arg] = params; o
      refine: (params={}) -> @merge params
      resolve: (target, context) ->
        resolver = @resolver
        return target unless resolver instanceof Function
        
        # TODO: qualify some internal meta params against passed-in target...
        context ?= target
        params = {}
        (target.get 'children').forEach (e) -> params[e.get 'name'] = e
        resolver.call context, (target.get 'name'), params, target

First we declare the compiler class as an extension of the
`meta-class`.  For details on `meta-class` please refer to
http://github.com/stormstack/meta-class

The primary function of the compiler is to `define` new language
extension statements and to `resolve` the extensions with custom
resolvers.  The `compile` operation uses these definitions to produce
the desired output.

    class YangMetaCompiler extends (require 'meta-class')
      @set map: {}, extension: {}, module: {}

      @map = (obj) -> @merge 'map', obj

      @extensions = (obj) ->
        (@get "extension.#{name}")?.resolver = resolver for name, resolver of obj

      @define: (name, params={}) ->
        extension = @get "extension.#{name}"
        unless extension?
          extension = new Extension name, params
          @set "extension.#{name}", extension
        #extension.refine params
        extension
            
      @resolver: (name, resolver) ->
        [ prefix..., name ] = (name.split ':' ) if typeof name is 'string'
        m = this
        m = m.get "module.#{prf}" for prf in prefix if prefix?
        extension = m.get "extension.#{name}"
        if resolver instanceof Function
          extension?.set? 'resolver', resolver
        extension ?= Extension
        extension

      @find: (type, name) ->
        [ prefix..., name ] = (name.split ':' ) if typeof name is 'string'
        m = this
        m = m.get "module.#{prf}" for prf in prefix if prefix?
        m.get "#{type}.#{name}"

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

      @define 'include',
        argument: 'module'
        resolver: (name, params) ->
          source = @get "map.#{name}"
          return unless typeof source is 'string'
          submodule = @compile ->
            path = require 'path'
            file = path.resolve (path.dirname module.parent?.filename), source
            console.log "INFO: including '#{name}' using #{file}"
            (require 'fs').readFileSync file, 'utf-8'
          @merge 'extension', submodule.get 'extension'
          submodule
          
## compiling a new module given input

The internal/private `compileStatement` function performs recursive compilation of
passed in statement and sub-statements and invoked within the cotext
of the originating `compile` function above.  It expects the
`statement` as an Object containing prf, kw, arg, and any substmts as
an array.

      compileStatement = (statement) ->
        return unless statement? and statement instanceof Object

        normalize = (statement) -> ([ statement.prf, statement.kw ].filter (e) -> e? and !!e).join ':'
        keyword = normalize statement

        results = (compileStatement stmt for stmt in statement.substmts).filter (e) -> e?
        class extends (require 'meta-class')
          @set yang: keyword, name: statement.arg, children: results 

The `compile` function is the primary method of the compiler which
takes in YANG text schema input and produces JS output representing
the input schema as meta data hierarchy.

It accepts various forms of input: a text string, a function, and a
meta class object.

      @compile: (input, parser=(require 'yang-parser')) ->
        return unless input?
        
        console.log "INFO: compiling a new module using extensions..."
        compiler = this
        input = (input.call this) ? input if input instanceof Function
        input = compileStatement (parser.parse schema=input) if typeof input is 'string'
        input.set "schema.#{input.get 'name'}", schema if schema?
        
The input module is then traversed to resolve the **currently known**
extensions for this compiler.

        input.traverse (parent, root) ->
          console.log @get 'yang'
          (compiler.find 'extension', (@get 'yang'))?.resolve this, root

Here we return the new `YangMetaCompiler` class for import and use by other
modules.

    module.exports = YangMetaCompiler

