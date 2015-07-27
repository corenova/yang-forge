Forge = require '../yangforge'

module.exports = Forge.Interface
  name: 'express'
  description: 'Fast, unopionated, minimalist web framework (HTTP/HTTPS)'
  generator: (opts) ->
    express = require 'express'
    app = (->
      bp = require 'body-parser'
      @use bp.urlencoded(extended:true), bp.json(strict:true), (require 'passport').initialize()

      env = process.env.NODE_ENV ? 'development'
      if env is 'production'
        @use (require 'errorhandler') {dumpExceptions: off, showStack: off}
        # the following will prevent production instance from crash...
        process.on 'uncaughtException', (err) ->
          console.log 'ALERT.. caught exception', err, err?.stack
      else
        console.log "running in #{env} mode"
        @use (require 'errorhandler') {dumpExceptions: on, showStack: on}
        @set 'json spaces', 2

      return this
    ).call express()

    opts.port ?= 5000
    console.info "express: listening on #{opts.port}".grey
    app.listen opts.port
    return app
    
