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
    @extension 'complex-type',  (key, value) -> @scope.define 'complext-type', key, value
    @extension 'abstract',      (key, value) -> undefined
    @extension 'extends',       (key, value) -> @merge (@scope.resolve 'complex-type', key) value
    @extension 'instance-type', (key, value) -> @bind key, (@scope.resolve 'complex-type', key) value
    @extension 'instance',      (key, value) -> @bind key, Forge.Model value
    @extension 'instance-list', (key, value) -> @bind key, Forge.List model: value

    # complex-type provides special handling for YANG 1.0
    # leaf/leaf-list extensions when used with 'type instance-identifier'

    @extension 'leaf', override: true, resolver: (key, value) ->
      @bind key, switch
        when Forge.Model.synthesized (value?.get? 'type') then Forge.BelongsTo value
        else Forge.Property value

    @extension 'leaf-list', override: true, resolver: (key, value) ->
      @bind key, switch
        when Forge.Model.synthesized (value?.get? 'type') then Forge.HasMany value
        else Forge.List value
