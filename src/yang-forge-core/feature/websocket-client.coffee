# socket.io (websocket client) feature interface module
#

module.exports = (to, opts) ->
  # should 'bind' to a runtime before use?
  @invoke (resolve, reject) ->
    socket = (require 'socket.io-client') to
    socket.on 'connect', =>
      console.log '[socket:%s] connected', socket.id
      modules = Object.keys(@properties)
      socket.once 'rooms', (rooms) ->
        rooms = rooms.filter (x) -> typeof x is 'string'
        console.log 'got rooms: %s', rooms
        # 1. join known rooms
        socket.emit 'join', rooms.filter (room) -> room in modules

        newRooms = rooms.filter (room) -> room not in modules
        if newRooms.length > 0
          # 2. request access for new rooms
          socket.emit 'knock', newRooms
      resolve socket
    socket.on 'infuse', (data) =>
      forge = @access 'yang-forge-core'
      # infuse the modules using keys
      forge?.invoke 'infuse', data
      .then (res) -> socket.emit 'join', res.get 'modules'
      .catch (err) -> console.error err
