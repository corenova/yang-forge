# engine - load and run cores

console.debug ?= console.log if process.env.yang_debug?

Maker = require './maker'

class Engine extends Maker.Container

  # an Engine runs Core(s)
  run: (cores...) -> cores.forEach (core) => core.invoke 'main', this

#
# declare exports
#
exports = module.exports = Engine
exports.Maker = Maker
