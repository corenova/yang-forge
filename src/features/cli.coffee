Forge = require '../yangforge'

module.exports = Forge.Interface
  name: 'cli'
  description: 'Command Line Interface'
  generator: ->
    app = this
    program = require 'commander'
    colors = require 'colors'

    # 1. Setup some default execution context
    meta = @constructor.extract 'version', 'description'
    program
      .version meta.version
      .description meta.description
      .option '--no-color', 'disable color output'

    for name, Action of (@access 'yangforge').meta 'rpc'
      continue unless Forge.Meta.instanceof Action

      rpc = Action.reduce()
      clionly = (rpc.meta['if-feature']) is 'cli'

      command = "#{name}"
      argument = rpc.input?.argument
      
      if argument?.meta.units?
        units = "#{argument.meta.units}"
        units += '...' if argument.meta.synth is 'list'
        command +=
          if argument.meta.required then " <#{units}>"
          else " [#{units}]"
      cmd = program.command command

      status = rpc.meta.status
      desc = rpc.meta.description
      cmd.description switch status
        when 'planned' then "#{desc} (#{status.cyan})"
        when 'deprecated' then "#{desc} (#{status.yellow})"
        when 'obsolete' then "#{desc} (#{status.red})"
        else desc

      for key, option of rpc.input?.options when key isnt 'meta'
        optstring = "--#{key}"
        if option.meta.units?
          optstring = "-#{option.meta.units}, #{optstring}"
        optstring += switch option.meta.type
          when 'empty' then ''
          else
            if option.meta.required then " <#{option.meta.type}>"
            else " [#{option.meta.type}]"  
        optdesc = option.meta.description
        if !!option.meta.default
          optdesc += " (default: #{option.meta.default})"

        defaultValue = switch option.meta.type
          when 'boolean' then (option.meta.default is 'true')
          else option.meta.default
        console.log "setting option #{key} with default: #{defaultValue}"
        cmd.option optstring, optdesc, defaultValue

      do (cmd, Action, status) ->
        cmd.action ->
          switch status
            when 'obsolete', 'planned'
              console.error "requested command is #{status} and cannot be used at this time".yellow
              cmd.help()
            when 'deprecated'
              console.warn "requested command has been #{status} and should no longer be used".yellow

          try
            [ argument, options ] = switch arguments.length
              when 2 then arguments
              when 1 then [ undefined, arguments[0] ]
              else
                [ args..., opt ] = arguments
                [ args, opt ]
            action = new Action input: argument: argument, options: options
            action
              .invoke app, "yangforge:#{options._name}"
              .then (res) ->
                console.log "action complete"
          catch e
            console.error "#{e}".red
            throw e
            cmd.help()

    program.parse process.argv
    program.help() unless program.args.length
    return program
