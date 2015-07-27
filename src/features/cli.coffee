Forge = require '../yangforge'

module.exports = Forge.Interface
  name: 'cli'
  description: 'Command Line Interface'
  generator: ->
    program = require 'commander'
    colors = require 'colors'

    # 1. Setup some default execution context
    meta = @constructor.extract 'version', 'description'
    program
      .version meta.version
      .description meta.description
      .option '--no-color', 'disable color output'

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

      for optname of method.get 'input.options'
        optstring = "--#{optname}"
        option = method.access "input.options.#{optname}"
        continue unless option?
        
        if option.meta 'units'
          optstring = "-#{option.meta 'units'}, #{optstring}"
        optstring += switch option.opts.type
          when 'empty' then ''
          else
            if option.opts.required then " <#{option.opts.type}>"
            else " [#{option.opts.type}]"  
        optdesc = option.meta 'description'
        if !!option.meta 'default'
          optdesc += " (default: #{option.meta 'default'})"

        defaultValue = switch option.opts.type
          when 'boolean' then (option.opts.default is 'true')
          else option.opts.default
        console.log "setting option #{optname} with default: #{defaultValue}"
        cmd.option optstring, optdesc, defaultValue

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
