# forge - load and build cores

console.debug ?= console.log if process.env.yang_debug?

Machine = require './machine'

class Forge extends Machine

  create: (cname, opts={}) ->
    opts.transform ?= true
    try
      console.debug? "[Forge:create] a new #{cname} core instance"
      core = @resolve 'core', cname
      # if opts.transform
      #   for xform in (core.get 'transforms') ? []
      return new core opts.config
    catch e
      console.error e
      return new Core config

  sign: ->

  publish: ->


#
# declare exports
#
exports = module.exports = new Forge
exports.Machine = Machine # for making new Machines
