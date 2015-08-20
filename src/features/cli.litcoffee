# Command-line interface feature module

This feature add-on module enables dynamic command-line interface
generation based on available runtime `module` instances.

It utilizes the [commander](http://github.com/tj/commander.js) utility
to dynamically construct the command line processing engine and
invokes upon generation to process the passed in command line
arguments.

## Source Code

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

        for action, meta of (@meta 'exports.rpc')
          continue unless Forge.Meta.instanceof meta

          rpc = meta.reduce()
          continue unless (rpc.meta['if-feature']?.hasOwnProperty 'cli')

          command = "#{action}"
          args = rpc.input?.arguments
          if args?.meta.config is true
            argstring = args.meta.description ? args.meta.type
            argstring += '...' unless args.meta['max-elements'] is '1'
            command +=
              if args.meta.required then " <#{argstring}>"
              else " [#{argstring}]"
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
              when 'boolean' then ''
              else
                if option.meta.required then " <#{option.meta.type}>"
                else " [#{option.meta.type}]"  
            optdesc = option.meta.description
            if !!option.meta.default
              optdesc += " (default: #{option.meta.default})"

            defaultValue = switch option.meta.type
              when 'boolean' then (option.meta.default is 'true')
              else option.meta.default
            if defaultValue? and !!defaultValue
              console.log "setting option #{key} with default: #{defaultValue}"
            cmd.option optstring, optdesc, defaultValue

          do (cmd, action, status) ->
            cmd.action ->
              switch status
                when 'obsolete', 'planned'
                  console.error "requested command is #{status} and cannot be used at this time".yellow
                  cmd.help()
                when 'deprecated'
                  console.warn "requested command has been #{status} and should no longer be used".yellow

              try
                [ args..., opts ] = arguments
                app.invoke action, arguments: ([].concat args...), options: opts
                  .then (res) ->
                    console.log "action '#{action}' completed"
                    if res? and res.serialize?
                      console.info res.serialize()
                  .catch (err) ->
                    console.error "#{err}".red
                    cmd.help()
              catch e
                console.error "#{e}".red
                cmd.help()

        program
          .command '*'
          .description 'specify a target module to run command-line interface'
          .action ->
            console.info arguments

        program.parse process.argv
        program.help() unless program.args.length
        return program
