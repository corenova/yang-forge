Forge = require 'yangforge'
module.exports = Forge.new module,
  after: ->
    sys = require 'child_process'
    @on 'send-echo', (input, output, done, origin) ->
      destination = input.get 'destination'
      unless destination?
        console.error "cannot issue ping without destination address"
        output.set 'echo-result', 2
        return done()
      child = sys.exec "ping -c 1 #{destination}", timeout: 2500
      child.on 'error', (err)  -> output.set 'echo-result', 2; done()
      child.on 'close', (code) -> output.set 'echo-result', code ? 1; done()
