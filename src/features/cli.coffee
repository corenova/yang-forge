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
      .description meta.description.blue

    for name, wrapper of (@access 'yangforge').methods
      method = wrapper?()
      continue unless method instanceof Forge.Meta

      clionly = (method.meta 'if-feature') is 'cli'

      status = method.meta 'status'
      status = 'missing' unless method.exec instanceof Function or status is 'planned'

      command = "#{name}"
      argument = method.access 'input.argument'
      if argument?.meta 'units'
        units = "#{argument.meta 'units'}"
        units += '...' if argument.opts.type is 'array'
        command +=
          if argument.opts.required then " <#{units}>"
          else " [#{units}]"
      cmd = program.command command

      desc = method.meta 'description'
      #desc += " [CLI]" if clionly
      cmd.description switch status
        when 'planned' then "#{desc} (#{status.cyan})"
        when 'deprecated' then "#{desc} (#{status.yellow})"
        when 'obsolete','missing' then "#{desc} (#{status.red})"
        else desc

      for opt of method.get 'input.options'
        optstring = "--#{opt}"
        option = method.access "input.options.#{opt}"
        continue unless option?
        
        if option.meta 'units'
          optstring = "-#{option.meta 'units'}, #{optstring}"
        unless option.opts.type is 'empty'
          optstring +=
            if option.opts.required then " <#{option.opts.type}>"
            else " [#{option.opts.type}]"  
        optdesc = option.meta 'description'
        if !!option.meta 'default'
          optdesc += " (default: #{option.meta 'default'})"
        cmd.option optstring, optdesc, option.meta 'default'

      do (cmd, method, status) =>
        cmd.action =>
          switch status
            when 'obsolete', 'missing', 'planned'
              console.error "requested command is #{status} and cannot be used".yellow
              cmd.help()
            when 'deprecated'
              console.warn "requested command has been #{status} and should no longer be used".yellow
          try method.exec.apply this, arguments
          catch e
            console.error "#{e}".red
            cmd.help()

    program.parse process.argv
    program.help() unless program.args.length
