# YANG Compiler (Version 1.0)

The YANG compiler is a YANG schema derived compiler that implements
the [RFC 6020](http://www.rfc-editor.org/rfc/rfc6020.txt) compliant
language extensions.  It is compiled by the `yang-meta-compiler` to
produce a new compiler that can then be used to compile any other v1
compatible YANG schema definitions into JS code.

Other uses of this compiler can be to compile yet another compiler
that can extend the YANG v1 extension keywords with other syntax that
can then natively support other YANG schemas without requiring the use
of `prefix` semantics to define the schema definitions deriving from
the extension keywords.

This `compiler` suite was created specifically to allow schema based
augmentation of the base YANG v1.0 language specifications, to
natively extend schema defined extensions for creating more powerful
abstractions on top of the underlying YANG data model schema language.

For an example of interesting ways new YANG compiler can be
extended, take a look at
[storm-compiler](http://github.com/stormstack/storm-compiler).

# Compiling a new Compiler

1. Specify the compiler that will be utilized to compile
2. Instantiate the compiler with `meta` data context
3. Compile the target schema with the configured compiler
4. Extend the compiled output with compiler used to compile

## 1. Specify the compiler

We first select the locally available `yang-meta-compiler` as the
initial compiler that will be used to generate the new YANG v1.0
Compiler.  Click [here](./yang-meta-compiler.litcoffee) to learn more
about the meta compiler.

    MetaCompiler = (require './yang-meta-compiler')

## 2. Instantiate a new MetaCompiler with configuration

As part of new MetaCompiler instantiation, we pass in various
configuration params to alter the behavior of the compiler during
`compile` operation.  The primary parameter for extending the
underlying extensions is the `resolver`.

    compiler = new MetaCompiler
      map: 'yang-v1-extensions': '../yang-v1-extensions.yang'

### Defining resolvers for YANG v1.0 extensions

The `resolver` is a JS function which is used by the `compiler` when
defined for a given YANG extension keyword to handle that particular
extension keyword.  It can resolve to a new class definition that will
house the keyword and its sub-statements (for container style
keywords) or perform a specific operation without returning any value
for handling non-data schema extensions such as import, include, etc.

The `resolver` function runs with the context of the `compiler` itself
so that the `this` keyword can be used to access any `meta` data or
other functions available within the given `compiler`.

      resolvers:
        module:    (self) -> self
        submodule: (self) -> self.set collapse: true
        feature:   (self, arg, params) -> @define 'feature', arg, params
        identity:  (self, arg, params) -> @define 'identity', arg, params
        typedef:   (self, arg, params) -> @define 'typedef', arg, params
        revision:  (self, arg, params) -> @define 'revision', arg, params

        type: (self) -> self

        container:    (self) -> self
        enum:         (self) -> self
        leaf:         (self) -> self
        'leaf-list':  (self) -> self
        list:         (self, arg, params) ->
          children = (self.get 'children').filter (e) -> not (self.instanceof e)
          self.reduce => @assembler.apply this, arguments
          class extends (require 'meta-class')
            @set yang: 'list', name: arg, model: self, children: children
            
        rpc:    (self) -> self.set action: true
        input:  (self) -> self
        output: (self) -> self
        
        notification: (self) -> self.set action: true

The `belongs-to` statement is only used in the context of a
`submodule` definition which is processed as a sub-compile stage
within the containing `module` defintion.  Therefore, when this
statement is encountered, it would be processed within the context of
the governing `compile` process which means that the metadata
available within that context will be made *eventually available* to
the included submodule.

        'belongs-to': (self, arg, params) -> @define 'module', params.prefix, (@resolve 'module', arg)
        
The `uses` statement references a `grouping` node available within the
context of the schema being compiled to return the contents at the
current `uses` node context.

        uses: (self, arg) -> @resolve 'grouping', arg
        grouping: (self, arg, params) ->
          self.set collapse: true
          @define 'grouping', arg, self

Here we associate a new `resolver` to the `augment` and `refine`
statement extensions.  The behavior of `augment` is to expand the
target-node identified by the `argument` with additional
sub-statements described by the `augment` statement.
      
        augment: (self, arg, params) -> @[arg]?.extend? params; undefined
        refine:  (self, arg, params) -> @[arg]?.extend? params; undefined

## 3. Compile using the target schema as input

Here we are loading the [schema](../yang-compiler.yang) file contents
and passing it into the `compiler` for the `compile` operation.

    output = compiler.compile ->
      path = require 'path'
      file = path.resolve __dirname, '../yang-compiler.yang'
      (require 'fs').readFileSync file, 'utf-8'

## 4. Configure the newly generated compiler with additional capabilities

    output.configure ->

Since we are creating a new compiler, we `mixin` the `MetaCompiler`
class into the new module.  This allows the resulting module to
provide `compile` operation for compiling other modules.

      @mixin MetaCompiler

We also include additional methods to the new `yang-compiler` to
support new extension resolvers as well as public use.

### Enhance the compiler with ability to process JSON input format
      
The `generate` function is a higher-order routine to `compile` where
it takes in a **meta data representation** of a given module to
produce the runtime JS class output.  This routine is internally
utilized for `import` workflow.

It accepts various forms of input: a JSON text string, a JS object, or
a function that returns one of the first two formats.

      Meta = require 'meta-class'

      @include generate: (input) ->
        input = (input.call this) if input instanceof Function
        obj = switch
          when typeof input is 'string'
            try (JSON.parse input) catch
          when input instanceof Object then input
          
        assert obj instanceof Object, "cannot generate using invalid input data"
        return obj if Meta.instanceof obj # if it is already meta class object, just return it

        meta = class extends Meta
          @merge obj
        assert typeof (meta.get 'schema') is 'string', "missing text schema to use for generate"

We then retrieve the **active** meta data (functions) and convert them
to actual runtime functions as necessary if they were provided as a
serialized string.
        
        actors = meta.extract 'resolvers', 'importers', 'handlers', 'hooks'
        for type, map of actors
          continue unless map instanceof Object
          for name, func of map
            continue if func instanceof Function
            try map[name] = eval "(#{func})" catch e then delete map[name]
            delete map[name] unless map[name] instanceof Function
              
Here we fork a child compiler to configure with necessary parameters
and then invoke the `compile` operation to produce a new runtime
module.

        @fork ->
          @set map: (meta.get 'map'), version: (meta.get 'version')
          @set actors
          @compile (meta.get 'schema')

### Enhance the compiler with ability to import external modules

The `import` function is a key new addition to the `yang-compiler`
over the underlying `yang-meta-compiler` which deals with infusing
external modules into current runtime context.

Here we register a few `importers` that the `yang-compiler` will
natively support.  The users of the `yang-compiler` can override or
add to these `importers` to support additional forms of input.

      path = require 'path'
      fs = require 'fs'
      
      readLocalFile = (filename) ->
        file = path.resolve (path.dirname module.parent?.filename), filename
        fs.readFileSync file, 'utf-8'

      @set importers:
        '^meta:.*\.json$': (input) -> readLocalFile input.file
        '^schema:.*\.yang$': (input) -> input.schema = readLocalFile input.file; input
        '^module:': (input) -> require input.file

The `import` routine allows a new module to be loaded into the current
compiler's internal metadata.  Since it will be auto-invoked during
the YANG schema `compile` process when it encounters `import`
statement, it would normally not need to be explicitly invoked.
However, in a number of scenarios, for initial loading of a new
module, it would be far more conveninent to use this mechanism than
using the lower-level `compile` routine by taking advantage of the
`importers` as well as the more powerful `generate` routine.

It expects an object as input which provides various properties, such
as name, source, map, resolvers, etc. 

      @include import: (input) ->
        assert input instanceof Object,
          "cannot call import without proper input object"
        
        exists = switch
          when Meta.instanceof input then input
          when Meta.instanceof input.source then input.source
          else @resolve 'module', input.name
        if exists?
          @define 'module', (exists.get 'name'), exists
          return exists
        
        input.source ?= @get "map.#{input.name}"

        assert typeof input.source is 'string' and !!input.source,
          "unable to initiate import without a valid source parameter"
          
        input.file ?= input.source.replace /^.*:/, ''

        # register any `importers` from metadata (if currently not defined)
        importers = (@get 'importers') ? {}
        for k, v of (@constructor.get 'importers')
          unless importers[k]?
            importers[k] = v
        @set "importers", importers

        for regex, importer of (@get 'importers') when (new RegExp regex).test input.source
          try payload = importer.call this, input
          catch e then console.log e; continue
          break if payload?

        assert payload?, "unable to import requested module using '#{input.source}'"

        # TODO: what to do if output name does not match input.name?
        output = @generate payload
        @define 'module', (output.get 'name'), output if output?
        output

The following `import` resolver utilizes the `import` functionality
introduced for the new compiler above.  It is declared here instead of
during MetaCompiler instantiation since dependency reference is
located here (mainly for readability).  In any event, it is
**generally safe** to associate such extension resolvers post-compile
operation but only if the extension is **not** used within the context
of the module schema definition that declares the extension.

      (@get 'extensions.import').refine
        resolver: (self, arg, params) ->
          mod = @import name: arg
          params.prefix ?= mod?.prefix
          @set "#{params.prefix}", (mod.extract 'exports', 'extensions')
          undefined

      (@get 'bindings.rpc.import').configure ->
        @include exec: (input) -> @import input

### Enhance the compiler with ability to export known modules

The `export` routine allows a known module (previously imported) into
the running compiler to be serialized into a output format for porting
across systems.

TODO: add exporters support similar to how we can add importers.

      @include export: (input) ->
        assert input instanceof Object, "invalid input to export module"
        assert typeof input.name is 'string' and !!input.name,
          "need to pass in 'name' of the module to export"
        format = input.format ? 'json'
        m = switch
          when (Meta.instanceof input) then input
          else @resolve 'module', input.name
        assert (Meta.instanceof m),
          "unable to retrieve requested module #{input.name} for export"

        tosource = require 'tosource'

        obj = m.extract 'name', 'schema', 'map', 'resolvers', 'importers', 'handlers'
        for key in [ 'resolvers', 'importers', 'handlers' ]
          obj[key]?.toJSON = ->
            @[k] = tosource v for k, v of this when k isnt 'toJSON' and v instanceof Function
            this
        
        return switch format
          when 'json' then JSON.stringify obj
        
Finally, we export the newly generated compiler.

    module.exports = output
