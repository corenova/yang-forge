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

1. Define configuration options for the compiler
2. Compile the target schema with the configured compiler
3. Mixin additional capabilities into the the newly generated compiler module

## 1. Define configuration options for the compiler

As part of new MetaCompiler instantiation, we pass in various
configuration params to alter the behavior of the compiler during
`compile` operation.  The primary parameter for extending the
underlying extensions is the `resolver`.

    options = 
      map: 'yang-v1-extensions': '../yang-v1-extensions.yang'

The `resolver` is a JS function which is used by the `compiler` when
defined for a given YANG extension keyword to handle that particular
extension keyword.  It can resolve to a new class definition that will
house the keyword and its sub-statements (for container style
keywords) or perform a specific operation without returning any value
for handling non-data schema extensions such as import, include, etc.

The `resolver` function runs with the context of the `compiler` itself
so that the `this` keyword can be used to access any `meta` data or
other functions available within the given `compiler`.

      extensions:
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
          self.reduce => @assembleNode.apply this, arguments
          class extends (require 'meta-class')
            @set yang: 'list', name: arg, model: self, children: children
            
        input:  (self) -> self
        output: (self) -> self
        rpc:    (self, arg) ->
          func = @get "procedures.#{arg}"
          self.configure ->
            @set action: true
            @include exec: func
        
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

The following `import` resolver utilizes the `import` functionality
introduced via the
[YangCompilerMixin](./yang-compiler-mixin.litcoffee) module.

        import: (self, arg, params) ->
          mod = @import name: arg
          params.prefix ?= mod?.prefix
          @define 'module', params.prefix, mod

      procedures:
        import: (input) -> @import input

## 2. Compile the target schema with the configured compiler

We select the locally available `yang-meta-compiler` as the initial
compiler that will be used to generate the new YANG v1.0 Compiler.
Click [here](./yang-meta-compiler.litcoffee) to learn more about the
meta compiler.

    MetaCompiler = (require './yang-meta-compiler')
    compiler = new MetaCompiler options

Here we are loading the [schema](../yang-compiler.yang) file contents
and passing it into the `compiler` for the `compile` operation.

    output = compiler.compile ->
      path = require 'path'
      file = path.resolve __dirname, '../yang-compiler.yang'
      (require 'fs').readFileSync file, 'utf-8'

## 3. Mixin additional capabilities into the the newly generated compiler module

Since we are creating a new compiler, we `mixin` the
[MetaCompiler](./yang-meta-compiler.litcoffee) module along with
additional extensions provided by
[YangCompilerMixin](./yang-compiler-mixin.litcoffee) module class into
the new module.  This allows the resulting module to provide `compile`
operation for compiling other modules along with other routines
provided by the mixins.

    output.mixin MetaCompiler, (require './yang-compiler-mixin')

Finally, we export the newly generated compiler.

    module.exports = output
