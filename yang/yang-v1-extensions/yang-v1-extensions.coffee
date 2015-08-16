###
YANG Version 1.0 Extensions

This submodule implements the [RFC
6020](http://www.rfc-editor.org/rfc/rfc6020.txt) compliant language
extensions.  It is used by `yangforge` to produce a new compiler that
can then be used to compile any other v1 compatible YANG schema
definitions into JS code.

The extensions are handled by utilizing the `data-synth` library which
provides contextual mapping for different types of extension
statements to logical JS object representations.

Writing new extensions for YANG language is very straight-forward as
long as the context for the callback function to handle the extension
is well understood.  For more details, please refer to documentation
found inside the main `yangforge` project.
###

# normally should be require 'yangforge' but this is internal dependency
Forge = require 'yangforge'

module.exports = Forge.new module,
  before: ->
    # The following extensions declare externally shared metadata
    # definitions about the module.  They are not attached into
    # the generated module's configuration tree but instead
    # defined in the metadata section of the module only.
    @extension 'identity', (key, value) -> @scope.define 'identity', key, value
    @extension 'feature',  (key, value) -> @scope.define 'feature', key, value
    @extension 'grouping', (key, value) -> @scope.define 'grouping', key, value
    @extension 'typedef',  (key, value) -> @scope.define 'type', key, value
    @extension 'rpc',      (key, value) -> @scope.define 'rpc', key, value
    @extension 'notification', (key, value) -> @scope.define 'notification', key, value

    @extension 'module', (key, value) ->
      @set exports: @scope.exports
      @extend info: -> (@get "bindings.#{key}").info()
      @include serialize: -> Forge.objectify (@get 'name'), (@access (@get 'name')).serialize()
      @bind 'name', key
      @bind key, Forge.Store value, ->
        @set name: key
        @info = (verbose=false) ->
          keys = [ 'name', 'prefix', 'namespace', 'description', 'revision', 'organization', 'contact' ]
          keys.push 'include', 'import' if verbose
          info = @extract.apply this, keys
          info.include =
            (@extract.apply data, keys for k, data of info.include) if info.include?
          info.import =
            (@extract.apply data, keys for k, data of info.import) if info.import?
          return info
          
    @extension 'submodule', (key, value) ->
      @set exports: @scope.exports
      @mixin value

    @extension 'import',  (key, value) -> @scope[key] = value?.extract? 'exports'
    @extension 'include', (key, value) -> @mixin value
    
    # The `belongs-to` statement is only used in the context of a
    # `submodule` definition which is processed as a sub-compile stage
    # within the containing `module` defintion.  Therefore, when this
    # statement is encountered, it would be processed within the context of
    # the governing `compile` process which means that the metadata
    # available within that context will be made *eventually available* to
    # the included submodule.
    @extension 'belongs-to', (key, value) -> @scope[value.get 'prefix'] = @scope

    @extension 'container', (key, value) -> @bind key, Forge.Object value
    @extension 'enum',      (key, value) -> null
    @extension 'leaf',      (key, value) ->
      @bind key, Forge.Property value, ->
        @set required: (@get 'mandatory') ? false

    @extension 'leaf-list', (key, value) -> @bind key, Forge.List value

    # The `list` is handled in a special way
    @extension 'list', (key, value) ->
      entry = Forge.Object (value.extract 'bindings')
      @bind key, (Forge.List value.unbind()).set type: entry

    # The following extensions makes alterations to the
    # configuration tree.  The `uses` statement references a
    # `grouping` node available within the context of the schema
    # being compiled to return the contents at the current `uses`
    # node context.  The `augment/refine` statements helps to
    # alter the containing statement with changes to the schema.
    @extension 'uses', (key, value) ->
      @mixin (@scope.resolve 'grouping', key), value
      for k, v  of value?.get? 'refine'
        orig = @unbind k ? Forge.Meta
        @bind k, (class extends orig).merge v
    @extension 'augment', (key, value) -> @bind key, value
    @extension 'refine',  (key, value) -> @merge "refine.#{key}", value

    @extension 'type', (key, value) ->
      @set 'type', (@scope.resolve 'type', key, false) ? key
      @merge value

    @extension 'config',    (key, value) -> @set 'config', key is 'true'
    @extension 'mandatory', (key, value) -> @set 'mandatory', key is 'true'
    @extension 'require-instance', (key, value) -> @set 'require-instance', key is 'true'

    @extension 'input',  (key, value) -> @bind 'input', value
    @extension 'output', (key, value) -> @bind 'output', value

