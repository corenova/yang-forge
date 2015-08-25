###
YANG comlex-types module

The YANG complex-types module provides additional Yang language
extensions according to [RFC
6095](http://tools.ietf.org/html/rfc6095). These extensions provide
mechanisms to manage the `complex-type` schema definitions which
essentially allows a given YANG data schema module to describe more
than one data models and to build relationships between the data
models.
###

Forge = require 'yangforge'
module.exports = Forge.new module,
  before: ->
    @extension 'complex-type',  (key, value) ->
      @scope.define 'complex-type', key, Forge.Model value, -> @set modelName: key, temp: false
      
    @extension 'abstract',      (key, value) -> undefined
    @extension 'extends',       (key, value) -> @merge (@scope.resolve 'complex-type', key)
    @extension 'instance-type', (key, value) ->
      ct = (@scope.resolve 'complex-type', key, false)
      unless ct?
        console.log "creating temporary complex-type for: #{key}"
        ct = Forge.Model temp: true
        @scope.define 'complex-type', key, ct
      @set type: ct

    @extension 'instance',      (key, value) -> @bind key, Forge.Model value
    @extension 'instance-list', (key, value) -> @bind key, Forge.List type: Forge.Model value

    # complex-type provides special handling for existing YANG 1.0 extensions
    # leaf: handle instance-identifier
    # leaf-list: handle instance-identifier
    @extension 'leaf', override: true, resolver: (key, value) ->
      @bind key, switch
        when Forge.Model.synthesized (value?.get? 'type') then Forge.BelongsTo value
        else Forge.Property value

    @extension 'leaf-list', override: true, resolver: (key, value) ->
      @bind key, switch
        when Forge.Model.synthesized (value?.get? 'type') then Forge.HasMany value
        else Forge.List value
