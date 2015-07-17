# YANG Compiler Mixin

We then define a new Mixin class to capture addtional capabilities we
want to infuse into the generated compiler output.

    Meta = (require 'data-synth').Meta
    
    class YangCompilerMixin extends Meta

## Enhance the compiler with ability to process JSON input format
      
The `generate` function is a higher-order routine to `compile` where
it takes in a **meta data representation** of a given module to
produce the runtime JS class output.  This routine is internally
utilized for `import` workflow.

It accepts various forms of input: a JSON text string, a JS object, or
a function that returns one of the first two formats.

      generate: (input=this) ->
        input = (input.call this) if input instanceof Function
        obj = switch
          when typeof input is 'string'
            try (JSON.parse input) catch
          when input instanceof Object then input
          
        assert obj instanceof Object, "cannot generate using invalid input data"
        return obj if Meta.instanceof obj # if it is already meta class object, just return it

        meta = (class extends Meta).merge obj
        assert typeof (meta.get 'schema') is 'string', "missing text schema to use for generate"

We then retrieve the **active** meta data (functions) and convert them
to actual runtime functions as necessary if they were provided as a
serialized string.
        
        actors = meta.extract 'extensions', 'importers', 'procedures', 'hooks'
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
          @compile (meta.get 'schema'), this

## Enhance the compiler with ability to import external modules

The `import` function is a key new addition to the `yang-compiler`
which deals with infusing external modules into current runtime
context.

Here we register a few `importers` that the `yang-compiler` will
natively support.  The users of the `yang-compiler` can override or
add to these `importers` to support additional forms of input.

      path = require 'path'
      fs = require 'fs'
      
      readLocalFile = (filename) ->
        file = path.resolve (path.dirname module.parent?.filename), filename
        fs.readFileSync file, 'utf-8'

      @importers =
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

      import: (input={}) ->
        assert input instanceof Object,
          "cannot call import without proper input object"
        
        exists = switch
          when Meta.instanceof input then input
          #when Meta.instanceof input.source then input.source
          else @resolve 'module', input.name
        if exists?
          @define 'module', (exists.get 'name'), exists
          return exists

        console.log "INFO: importing '#{input.name}'"
        try
          pkg = (require input.name)
        catch e then console.log e
          
        @define 'module', input.name, output if output?
        return output
        
        # input.source ?= @get "map.#{input.name}"
        # assert typeof input.source is 'string' and !!input.source,
        #   "unable to initiate import without a valid source parameter"
        # input.file ?= input.source.replace /^.*:/, ''

        # # register any `importers` from metadata (if currently not defined)
        # importers = (@get 'importers') ? {}
        # for k, v of (@constructor.importers)
        #   unless importers[k]?
        #     importers[k] = v
        # @set "importers", importers

        # for regex, importer of (@get 'importers') when (new RegExp regex).test input.source
        #   try payload = importer.call this, input
        #   catch e then console.log e; continue
        #   break if payload?

        # assert payload?, "unable to import requested module using '#{input.source}'"

        # TODO: what to do if output name does not match input.name?
        output = @generate payload
        @define 'module', input.name, output if output?
        output

## Enhance the compiler with ability to export known modules

The `export` routine allows a known module (previously imported) into
the running compiler to be serialized into a output format for porting
across systems.

TODO: add exporters support similar to how we can add importers.

      export: (input) ->
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

        obj = m.extract 'name', 'schema', 'map', 'extensions', 'importers', 'exporters', 'procedures'
        for key in [ 'extensions', 'importers', 'procedures' ]
          obj[key]?.toJSON = ->
            @[k] = tosource v for k, v of this when k isnt 'toJSON' and v instanceof Function
            this
        
        return switch format
          when 'json' then JSON.stringify obj

    module.exports = YangCompilerMixin
