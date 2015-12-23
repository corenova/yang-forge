# socket.io (websockets) feature interface module
#

module.exports = 
  # should 'bind' to a runtime before use
  connect: (to, opts) ->
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
        forge = @access 'yangforge'
        # infuse the modules using keys
        forge?.invoke 'infuse', data
        .then (res) -> socket.emit 'join', res.get 'modules'
        .catch (err) -> console.error err

  run: (model, runtime) ->
    app = model.parent
    server = runtime.express?.server
    console.info "websocket: binding forgery to /socket.io".grey
    io = (require 'socket.io') server
    io.on 'connection', (socket) ->
      room = socket.join 'yangforge'

    # watch app and send events
    app.on 'attach', (name, module) ->
      console.debug? "attached #{name}"
      source = module?.parent?.constructor.toSource? format: 'yaml'
      io.to('yangforge').emit 'infuse', sources: source if source?
    return io

  send: (to, data, resolve, reject) ->
