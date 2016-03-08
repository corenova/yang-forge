# machine - load and run cores

console.debug ?= console.log if process.env.yang_debug?

Maker = require './maker'

class Machine extends Maker.Container

  infuse: (cores...) ->

  enable: (core, opts={}) ->

  disable: (core) ->

  # a Machine runs only once
  run: ->

    @running = true

  terminate: ->


#
# declare exports
#
exports = module.exports = Machine
exports.Maker = Maker
