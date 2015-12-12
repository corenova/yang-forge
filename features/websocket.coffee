# socket.io (websockets) feature interface module
#

module.exports = 
  config:
    port: 8080

  run: (model, runtime) ->
    app = model.parent
    server = runtime.express?.server ? @config.port
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
