Forge = require 'yangforge'
module.exports = Forge.new module,
  after: ->
    sys = require 'child_procss'
    @on 'ping:send-echo', (input, output, done) ->
      child = sys.exec "ping -c 1 #{input.get 'destination'}", timeout: 5000
      child.on 'error', (err) -> done err
      child.on 'close', (code) -> output.set 'echo-result', code; done()
