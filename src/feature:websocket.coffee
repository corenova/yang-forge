# socket.io (websockets) feature interface module
#

module.exports = ->
  console.info "websocket: binding core to /socket.io".grey
  io = (require 'socket.io') @express?.server
  io.on 'connection', (socket) ->
    room = socket.join 'yang-forge-core'

  # watch core and send events
  @on 'merge', (cores...) ->
    io.to('yang-forge-core')
      .emit 'infuse', cores: cores.map (x) -> x.dump()

  return io
