# machine - load and run cores

console.debug ?= console.log if process.env.yang_debug?

Maker = require './maker'

class Machine extends Maker.Container

  infuse: (cores...) ->

  enable: (cname, opts={}) ->
    Core = @resolve 'core', cname
    
    @feature[name] ?= (@meta "feature.#{name}")?.construct? options

  disable: (cname) ->
    @feature[name]?.destroy?()
    delete @feature[name]

  # a Machine runs only once
  run: ->

    @running = true

  terminate: ->

  run: (features...) ->
    if 'cli' in features
      (@resolve 'feature', 'cli').run this
      return

    options = features
      .map (e) ->
        unless typeof e is 'object'
          synth.objectify e, on
        else e
      .reduce ((a, b) -> synth.copy a, b, true), {}

    (@access 'yangforge').invoke 'run', options: options
    .catch (e) -> console.error e


#
# declare exports
#
exports = module.exports = Machine
exports.Maker = Maker
