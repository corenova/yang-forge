YangCoreCompiler
================

The **YangCoreCompiler** class provides support for basic set of YANG
schema modeling language by using the built-in *extension* syntax to
define additional schema language constructs.

The core compiler only supports bare minium set of YANG statements and
should be used only to generate a new compiler such as
'yang-v1-compiler' which implements the version 1.0 of the YANG
language specifications.

First we declare the compiler class as an extension of the
`meta-class`.  For details on `meta-class` please refer to
http://github.com/stormstack/meta-class

    MetaClass = require 'meta-class'
    class YangCoreCompiler extends MetaClass

We initialize the `meta` data of this class by setting up built-in
supported extension keywords.

      @set
        module:
          resolver: (arg, params) -> class extends this
          extension: '0..n'
          supplement: '0..n'
        extension:
          resolver: (arg, params) -> @merge arg, params; null
          argument: '0..1'
          description: '0..1'
          reference: '0..1'
          status: '0..1'
          sub: '0..n' # non YANG 1.0 compliant
        argument: 'yin-element': '0..1'
        description: 'argument text': 'yin-element': true
        reference: 'argument text': 'yin-element': true
        status: argument: 'value'
        value: argument: 'value'
        'yang-version': argument: 'value'
        'yin-element': argument: 'value'

The below `sub` statement is **not** a part of Yang 1.0 specification,
but provided as part of the `yang-core-compiler` so that it can be
used to provide constraint enforcement around sub-statements validity
and cardinality when a new statement extended via the schema
`extension` facility.

        sub:
          argument: 'extension-name'
          resolver: (arg, params) -> params?.value
          value: '0..1'

The below `supplement` statement is also **not** a part of Yang 1.0
specification, but provided as part of the `yang-core-compiler` so
that it can be used to provide schema driven augmentations to
pre-defined extension statements.

        supplement:
          argument: 'extension-name'
          resolver: (arg, params) -> @merge arg, params; null
          sub: '0..n'

We specify basic parser function to process YANG text-based schema as
input into `compile` routine.

      @parser: require 'yang-parser'

The `preprocess` function is used to extract meta data from the passed
in schema so that it can be augmented prior to `compile` operation is
invoked on the schema by passing in the optional revised `context`.

      @preprocess: (schema) ->
        statement = @parser.parse schema
        return unless statement?
        extensions = {}
        for stmt in statement.substmts when stmt.kw is 'extension'
          params = {}
          for substmt in stmt.substmts when substmt.substmts.length is 0
            params[substmt.kw] = substmt.arg
          extensions[stmt.arg] = params
        class extends MetaClass
          @set extensions

The `compile` function is the primary method of the compiler which
takes in YANG schema input and produces JS output representing the
input schema.  When called with `context`, it is merged into the meta
data of the compiler to be used during the `compile` processing.  The
passed in `context` should be a derivative of the meta data extracted
via `preprocess` call prior to calling `compile`.

      @compile: (schema, meta={}) ->
        return unless schema?
        (@merge meta) if meta instanceof Function
        output = @compileStatement (@parser.parse schema)
        output?.value

The `compileStatement` function performs recursive compilation of
passed in statement and sub-statements and invoked within the cotext
of the originating `compile` function above.  It expects the
`statement` as an Object containing prf, kw, arg, and any substmts as
an array.

      @compileStatement: (statement) ->
        return unless statement? and statement instanceof Object

        if !!statement.prf
          target = (@get statement.prf)?.get? statement.kw
        else
          target = @get statement.kw

        normalize = (statement) -> ([ statement.prf, statement.kw ].filter (e) -> e? and !!e).join ':'
        # keyword = normalize statement
        # target = @get keyword

        unless target?
          console.log "WARN: unrecognized keyword extension '#{normalize statement}', skipping..."
          return null
          
        # TODO - add enforcement for cardinality specification '0..1', '0..n', '1..n' or '1'
        results = (@compileStatement stmt for stmt in statement.substmts when switch
          # when not (meta = @get keyword)?
          #   console.log "WARN: unable to find metadata for #{keyword}"
          #   false
          when not (target.hasOwnProperty stmt.kw)
            console.log "WARN: #{statement.kw} does not have sub-statement declared for #{stmt.kw}"
            false
          else true
        )
        params = (results.filter (e) -> e? and e.value?).reduce ((a,b) -> a[b.name] = b.value; a), {}
        value = switch
          when target.resolver instanceof Function
            target.resolver.call this, statement.arg, params, target
          when (Object.keys params).length > 0
            class extends MetaClass
          else
            statement.arg

        value?.set? yang: statement.kw
        value?.extend? params

        (@set "#{statement.kw}:#{statement.arg}", value) if statement.arg? and value instanceof Function

        return switch
          when (Object.keys params).length > 0
            name: (statement.arg ? statement.kw), value: value
          else
            name: statement.kw, value: value

Here we return the new `YangCoreCompiler` class for import by other
modules.

    module.exports = YangCoreCompiler
