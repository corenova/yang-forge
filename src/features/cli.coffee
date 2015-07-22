program = require 'commander'

class CommandLineInterfaceMixin

  @bind 'interface.cli', -> undefined

module.exports = CommandLineInterfaceMixin

program
  .version (Forge.get 'version')
