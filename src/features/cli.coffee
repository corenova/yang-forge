Forge = require '../yangforge'

module.exports = Forge.Interface
  name: 'cli'
  description: 'Command Line Interface'
  generator: ->
    program = require 'commander'

    # 1. Setup some default execution context
    meta = @constructor.extract 'version', 'description'
    program
      .version meta.version
      .description meta.description

    for name, wrapper of (@access 'yangforge').methods
      method = wrapper?()
      continue unless method instanceof Forge.Meta

      cmdstring = "#{name}"
      argument = method.access 'input.argument'
      if argument?.meta 'units'
        units = "#{argument.meta 'units'}"
        units += '...' if argument.opts.type is 'array'
        cmdstring += " [#{units}]"

      cmd = program
        .command cmdstring
        .description method.meta 'description'

      for opt, val of method.get 'input.options'
        optstring = "--#{opt}"
        option = method.access "input.options.#{opt}"
        if option?.meta 'units'
          optstring = "-#{option.meta 'units'}, #{optstring}"
        unless option?.opts.type is 'empty'
          optstring += " #{option.opts.type}"
        cmd.option optstring, option.meta 'description'

      do (method) =>
        cmd.action =>
          try method.exec.apply this, arguments
          catch e then console.error "requested command failed\n#{e}"

    program.parse process.argv
    program.help() unless program.args.length
