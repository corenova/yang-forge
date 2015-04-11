Yang Version 1.0 Compiler
=========================

The Yang v1 compiler is a Yang schema derived compiler that implements
the [RFC 6020](http://www.rfc-editor.org/rfc/rfc6020.txt) compliant
language extensions.  It is compiled by the `yang-core-compiler` to
produce a new compiler that can then be used to compile any other v1
compatible Yang schema definitions into JS code.

Other uses of this compiler can be to compile yet another compiler
that can extend the Yang v1 extension keywords with other syntax that
can then natively support other Yang schemas without requiring the use
of `prefix` semantics to define the schema definitions deriving from
the extension keywords.

This `compiler` suite was created specifically to allow schema based
augmentation of the base YANG v1.0 language specifications, to
natively extend schema defined extensions for creating more powerful
abstractions on top of the underlying YANG data model schema language.

For an example of interesting ways new YANG compiler can be
extended, take a look at
[yang-storm](http://github.com/stormstack/yang-storm).

Compiling a new Compiler
------------------------

1. Specify the compiler that will be utilized to compile
2. Configure the compiler with `meta` data context
3. Compile the target schema with the configured compiler
6. Extend the compiled output with compiler used to compile

Below we select the locally available `yang-core-compiler` as the
initial compiler that will be used to generate the new Yang v1.0
Compiler.  Click [here](./yang-core-compiler.litcoffee) to learn more
about the core compiler.

    compiler = (require './yang-core-compiler').configure ->
      
The `meta` data represents the set of **rules** that the `compiler`
will utilize during `compile` operation.  The primary parameter for
extending the underlying `meta` data is the `resolver`.

The `resolver` is a JS function which is used by the `compiler` when
defined for a given Yang extension keyword to handle that particular
extension keyword.  It can resolve to a new class definition that will
house the keyword and its sub-statements (for container style
keywords) or perform a specific operation without returning any value
for handling non-data schema extensions such as import, include, etc.

The `resolver` function runs with the context of the `compiler` itself
so that the `this` keyword can be used to access any `meta` data or
other functions available within the `compiler`.
  
Other parameters can be passed in during `meta` data augmentation as a
collection of key/value pairs which inform what the valid
substatements are for the given extension keyword.  The `key` is the
name of the extension that can be further defined under the given
extension and the `value` specifies the **cardinality** of the given
sub statement (how many times it can appear under the given
statement). This facility is provided here due to the fact that Yang
version 1.0 language definition does not provide a sub-statement
extension to the `extension` keyword to specify such constraints.

Here we associate a new `resolver` to the `augment` statement
extension.  The behavior of `augment` is to expand the target-node
identified by the `argument` with additional sub-statements described
by the `augment` statement.

      @merge 'yang/augment', resolver: (arg, params) -> @[arg]?.extend? params; null

For below `import` and `include` statements, special resolvers are
associated to handle accessing the specified `argument` within the
scope of the current schema being compiled.
      
      @merge 'yang/import', resolver: (arg, params) -> @set "module/#{params.prefix}", (@get "module/#{arg}"); null
      @merge 'yang/include', resolver: (arg, params) -> @extend (@get "submodule/#{arg}"); null

The `belongs-to` statement is only used in the context of a
`submodule` definition which is processed as a sub-compile stage
within the containing `module` defintion.  Therefore, when this
statement is encountered, it would be processed within the context of
the governing `compile` process which means that the metadata
available within that context will be made *eventually available* to
the included submodule.

      @merge 'yang/belongs-to', resolver: (arg, params) -> @set "module/#{params.prefix}", (@get "module/#{arg}"); null

The `refine` statement uses similar extend capability as `augment`.

      @merge 'yang/refine', resolver: (arg, params) -> @[arg]?.extend? params; null

The `uses` statement references a `grouping` node available within the
context of the schema being compiled to return the contents at the
current `uses` node context.

      @merge 'yang/uses', resolver: (arg, params) -> @get "grouping/#{arg}"

Specify the 'meta' type statements so that they are only added into
the metadata section of the compiled output.

      @merge 'yang/feature',  meta: true
      @merge 'yang/grouping', meta: true
      @merge 'yang/identity', meta: true
      @merge 'yang/revision', meta: true
      @merge 'yang/typedef',  meta: true

Specify the statements that should be added to the configuration
defintions but also added into the metadata section of the compiled
output.

      @merge 'yang/module',       export: true
      @merge 'yang/submodule',    export: true
      @merge 'yang/rpc',          export: true
      @merge 'yang/notification', export: true
      
Finally, compile the [schema](../schemas/yang-v1-compiler.yang) with
the newly configured `compiler` and extend the output with the
compiler used to generate the output.

    output = compiler.compile (compiler.readSchema 'yang-v1-compiler.yang')
    output.extend compiler

    module.exports = output
