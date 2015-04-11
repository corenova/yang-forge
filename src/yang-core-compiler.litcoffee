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

Setup a default `schemadir` to be a relative directory location
(../schemas) from this file.
      
      @set 'schemadir', (require 'path').resolve __dirname, '../schemas'
      
We initialize the `meta` data of this class by setting up built-in
supported extension keywords.

      @set
        'yang/module':
          resolver: (arg, params) -> class extends this
          extension: '0..n'
          supplement: '0..n'
        'yang/extension':
          resolver: (arg, params) -> @merge "yang/#{arg}", params; null
          argument: '0..1'
          description: '0..1'
          reference: '0..1'
          status: '0..1'
          sub: '0..n' # non YANG 1.0 compliant
        'yang/argument': 'yin-element': '0..1'
        'yang/description': 'argument text': 'yin-element': true
        'yang/reference': 'argument text': 'yin-element': true
        'yang/status': argument: 'value'
        'yang/value': argument: 'value'
        'yang/yang-version': argument: 'value'
        'yang/yin-element': argument: 'value'

The below `sub` statement is **not** a part of Yang 1.0 specification,
but provided as part of the `yang-core-compiler` so that it can be
used to provide constraint enforcement around sub-statements validity
and cardinality when a new statement extended via the schema
`extension` facility.

        'yang/sub':
          argument: 'extension-name'
          resolver: (arg, params) -> params?.value
          value: '0..1'

The below `supplement` statement is also **not** a part of Yang 1.0
specification, but provided as part of the `yang-core-compiler` so
that it can be used to provide schema driven augmentations to
pre-defined extension statements.

        'yang/supplement':
          argument: 'extension-name'
          resolver: (arg, params) -> @merge "yang/#{arg}", params; null
          sub: '0..n'
     
The `configure` function accepts a function as an argument which will apply
against this class for setup/initialization.

      @configure: (func) ->
        func?.apply? this
        this

The `use` function specifies one or more extension components to merge
the `meta` data into the `compiler` for reference during the `compile`
process.

      @use: (components...) ->
        (@merge component) for component in components when component instanceof Function

The `readSchema` function is used to retrieve a local file from
specified `schemadir` as a helper input into `compile` routine.

      @readSchema: (name) ->
        file = (require 'path').resolve (@get 'schemadir'), name
        console.log "readSchema: #{file}..."
        try (require 'fs').readFileSync file, 'utf-8'
        catch
          console.log "WARN: unable to read from source #{arg}"
          undefined

We specify basic parser function to process YANG text-based schema as
input into `compile` routine.

      @parser: require 'yang-parser'

The `compile` function is the primary method of the compiler which
takes in YANG schema input and produces JS output representing the
input schema.

      @compile: (schema) ->
        return unless schema?
        output = @compileStatement (@parser.parse schema)
        if (output?.value?.get? 'yang') is 'module'
          output.value.merge (this.match /.*\/.*/) # merge exported metadata
        output?.value

The `compileStatement` function performs recursive compilation of
passed in statement and sub-statements and invoked within the cotext
of the originating `compile` function above.  It expects the
`statement` as an Object containing prf, kw, arg, and any substmts as
an array.

      @compileStatement: (statement) ->
        return unless statement? and statement instanceof Object

        if !!statement.prf
          console.log "INFO: processing prefix keyword #{statement.prf}:#{statement.kw}"
          console.log @get "module/#{statement.prf}"
          target = (@get "module/#{statement.prf}")?.get? "yang/#{statement.kw}"
        else
          target = @get "yang/#{statement.kw}"

        normalize = (statement) -> ([ statement.prf, statement.kw ].filter (e) -> e? and !!e).join ':'
        # keyword = normalize statement
        # target = @get keyword

        unless target?
          console.log "WARN: unrecognized keyword extension '#{normalize statement}', skipping..."
          return null

        # Special treatment of 'module' by temporarily declaring itself into the metadata
        if statement.kw is 'module'
          @set "module/#{statement.arg}", this
          
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

        (@set "#{statement.kw}/#{statement.arg}", value) if (target.export is true) or (target.meta is true)

        if target.meta is true
          return null

        return switch
          when statement.substmts?.length > 0
            name: (statement.arg ? statement.kw), value: value
          else
            name: statement.kw, value: value

Here we return the new `YangCoreCompiler` class for import by other
modules.

    module.exports = YangCoreCompiler
