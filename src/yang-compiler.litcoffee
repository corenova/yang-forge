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

It is **important** to note that the compiler is used to generate
**runtime** JS class object hierarchy - which means that immediately
following the schema compilation, the resulting output can be
instatiated via `new` keyword to bring the compiled output to life.

For an example of interesting ways new YANG compiler can be
extended, take a look at
[storm-compiler](http://github.com/stormstack/storm-compiler).

# Compiling a new Compiler

1. Define configuration options for the compiler
2. Compile the target schema with the configured compiler
3. Mixin additional capabilities into the the newly generated compiler module

## 1. Define configuration options for the compiler

As part of new MetaCompiler instantiation, we pass in various
configuration `options` to alter the behavior of the compiler during
`compile` operation.

As part of configuration options, we can specify various JS functions
to handle the YANG `extensions` during the `compile` process.  It is
invoked in the context of the containing statement (parent object) and
it can alter how it is related/used in the containing statemnt
context.  The return value of the extension resolving functions are
ignored.  It can also access `@compiler` to perform additional
operations available to the `@compiler` as it operates on the given
extension.

    Meta = require 'meta-class'

    options = 
      map: 'yang-v1-extensions': '../yang-v1-extensions.yang'

      extensions:
        # The following extension resolvers deal with configuration
        # hierarchy definition statements.
        module:      (key, value) -> @mixin value
        container:   (key, value) -> @bind key, value
        enum:        (key, value) -> @bind key, value
        leaf:        (key, value) -> @bind key, value
        'leaf-list': (key, value) -> @bind key, value
        list:        (key, value) -> @bind key, (class extends Meta).set model: value

        # The following extensions declare externally shared metadata
        # definitions about the module.  They are not attached into
        # the generated module's configuration tree but instead
        # defined in the metadata section of the module only.
        grouping: (key, value) -> @compiler.define 'grouping', key, value
        typedef:  (key, value) -> @compiler.define 'type', key, value

        # The following extensions makes alterations to the
        # configuration tree.  The `uses` statement references a
        # `grouping` node available within the context of the schema
        # being compiled to return the contents at the current `uses`
        # node context.  The `augment/refine` statements helps to
        # alter the containing statement with changes to the schema.
        uses: (key, value) ->
          Grouping = (@compiler.resolve 'grouping', key) ? Meta
          @mixin (class extends Grouping).merge value
        augment: (key, value) -> @merge value
        refine:  (key, value) -> @merge value

        type: (key, value) ->
          Type = @compiler.resolve 'type', key
          @set 'type', Type if Type?

        rpc: (key, value) ->
          @set "methods.#{key}", value
          @bind key, @compiler.get "procedures.#{key}"

        input:  (key, value) -> @bind 'input', value
        output: (key, value) -> @bind 'output', value

        notification: (key, value) -> @compiler.define 'notification', key, value

        # The `belongs-to` statement is only used in the context of a
        # `submodule` definition which is processed as a sub-compile stage
        # within the containing `module` defintion.  Therefore, when this
        # statement is encountered, it would be processed within the context of
        # the governing `compile` process which means that the metadata
        # available within that context will be made *eventually available* to
        # the included submodule.
        'belongs-to': (key, value) ->
          @compiler.define 'module', (value.get 'prefix'), (@compiler.resolve 'module', key)

        # The following `import` resolver utilizes the `import` functionality
        # introduced via the
        # [YangCompilerMixin](./yang-compiler-mixin.litcoffee) module.
        import: (key, value) ->
          mod = @compiler.import name: key
          prefix = (value.get 'prefix') ? (mod.get 'prefix')
          @compiler.define 'module', prefix, mod

      procedures:
        import: (input) -> @import input

## 2. Compile the target schema with the compiler using options

We select the locally available `yang-meta-compiler` as the initial
compiler that will be used to generate the new YANG v1.0 Compiler.
Click [here](./yang-meta-compiler.litcoffee) to learn more about the
meta compiler.

Here we are loading the [schema](../yang-compiler.yang) file contents
and passing it into the `compiler` for the `compile` operation.

    MetaCompiler = (require './yang-meta-compiler')
    compiler = new MetaCompiler options
    
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
