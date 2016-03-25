# Command-line interface feature module
#
# This feature add-on module enables dynamic command-line interface
# generation based on available runtime `app` instance.
#
# It utilizes the [commander](http://github.com/tj/commander.js) utility
# to dynamically construct the command line processing engine and
# invokes upon generation to process the passed in command line
# arguments.
program = require 'commander'
colors  = require 'colors'
assert  = require 'assert'

module.exports = (name, argv) ->
  model = @access name
  assert model?,
    "unable to locate '#{name}' module inside current core"

  # 1. Setup some default execution context
  program
    .version Object.keys(model.meta 'revision')[0]
    .description (model.meta 'description')
    .option '--no-color', 'disable color output'
    .option '-v, --verbose', 'increase verbosity', false

  for action, rpc of (model.meta 'rpc')
    continue unless rpc['if-feature'] is 'cli'

    status = rpc.status
    command = "#{action}"
    if rpc.input?['leaf-list']?.arguments?
      args = rpc.input['leaf-list'].arguments
      if args?.config is true
        argstring = args.units ? args.type
        argstring += '...' unless args['max-elements'] is 1
        command +=
          if args.mandatory then " <#{argstring}>"
          else " [#{argstring}]"

    cmd = program.command command
    cmd.description switch status
      when 'planned' then "#{rpc.description} (#{status.cyan})"
      when 'deprecated' then "#{rpc.description} (#{status.yellow})"
      when 'obsolete' then "#{rpc.description} (#{status.red})"
      else rpc.description

    if rpc.input?.container?.options?
      for ext, v of rpc.input.container.options when typeof v is 'object'
        for key, option of v
          optstring = "--#{key}"
          if option.units?
            optstring = "-#{option.units}, #{optstring}"
          type = option.type
          if type instanceof Object
            for tname, params of type
              if tname is 'enumeration'
                type = Object.keys(params.enum).join '|'
              else
                type = tname
              break;
          optstring += switch type
            when 'boolean','empty' then ''
            else
              if option.mandatory then " <#{type}>"
              else " [#{type}]"
          optdesc = option.description
          if !!option.default
            optdesc += " (default: #{option.default})"

          args = [ optstring, optdesc ]
          switch
            when option.default? and !!option.default
              console.debug? "setting option #{key} with default: #{option.default}"
              args.push switch type
                when 'boolean' then (option.default is 'true')
                else option.default

            when ext is 'leaf-list'
              console.debug? "setting option #{key} with accumulation func"
              args.push ((x,y) -> y.concat x), []

          cmd.option args...

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
          model.invoke action, arguments: ([].concat args...), options: opts
            .then (res) ->
              console.debug? "action '#{action}' completed"
              console.info res.get()
            .catch (err) ->
              if program.verbose
                console.error err
              console.error "#{err}".red
        catch e
          console.error "#{e}".red
          cmd.help()

  program.parse argv
  return program
