# REST/JSON interface feature module

This feature add-on module enables dynamic REST/JSON interface
generation based on available runtime `module` instances.

It utilizes the underlying [express](express.litcoffee) feature add-on
to dynamically create routing middleware and associates various HTTP
method facilities according to the available runtime `module`
instances.

## Source Code

    Forge = require '../yangforge'
    module.exports = Forge.Interface
      name: 'restjson'
      description: 'REST/JSON web services interface generator'
      needs: [ 'express' ]
      generator: (app) ->
        console.log "generating REST/JSON interface..."
        express = require 'express'

        restjson = express.Router()
        restjson.all '*', (req, res, next) => req.module = this; next()

**Primary Module routing endpoint**
        
        router = express.Router()
        router.param 'module', (req,res,next,module) ->
          match = req.module.access "modules.#{module}"
          if match? then req.module = match; next() else next 'route'

        router.param 'operation', (req,res,next,operation) ->
          console.assert req.module?,
            "cannot perform '#{operation}' without containing module"
          match = req.module.access "methods.#{operation}"
          if match? then req.rpc = match; next() else next 'route'

        router.param 'container', (req,res,next,container) ->
          match = req.module.access "#{req.module.get 'name'}.#{container}"
          if (match?.meta 'yang') in [ 'container', 'list', 'leaf-list' ]
            req.container = match; next()
          else next 'route'

        router.route '/'
        .all (req, res, next) ->
          # XXX - verify req.user has permissions to operate on the forgery
          next()
        .options (req, res, next) ->
          res.send
            REPORT:
              description: 'get detailed information about this resource'
            GET:
              description: 'get serialized output for this resource'
            PUT:
              description: 'update configuration for this resource'
            COPY:
              description: 'get a copy of this resource for cloning it elsewhere'
        .report (req, res, next) -> res.locals.result = req.module.report(); next()
        .get    (req, res, next) -> res.locals.result = req.module.serialize(); next()
        .put    (req, res, next) ->
          (req.module.set req.body).save()
          .then (result) ->
            res.locals.result = result.serialize();
            next()
          .catch (err) ->
            req.module.rollback()
            next err
        .copy   (req, res, next) ->
          # XXX - generate JSON serialized copy of this forge
          next()

        router.route '/:operation'
        .options (req, res, next) ->
          keys = Forge.Property.get 'options'
          keys.push 'description', 'reference', 'status'
          collapse = (obj) ->
            return obj unless obj instanceof Object
            for k, v of obj when k isnt 'meta'
              obj[k] = collapse v
            for k, v of obj.meta when k in keys
              obj[k] = v
            delete obj.meta
            return obj
          res.send
            POST: collapse req.rpc.meta.reduce()
        .post (req, res, next) ->
          console.info "restjson: invoking rpc operation '#{req.rpc.name}'".grey
          req.module.invoke req.rpc.name, req.body, req.module
            .then  (output) -> res.locals.result = output.get(); next()
            .catch (err) -> next err

**/:container/* configuration tree routing endpoint**

        subrouter = express.Router()
        subrouter.param 'container', (req,res,next,container) ->
          match = req.container.access container
          if (match?.meta 'yang') in [ 'container', 'list', 'leaf-list' ]
             req.container = match; next()
          else next 'route'
        subrouter.route '/'
        .get (req, res, next) -> res.locals.result = req.container.serialize(); next()
        subrouter.use '/:container', subrouter

        # nested sub-routes for containers and modules
        router.use '/:container', subrouter
        router.use '/:module', router

**Default routing middleware handlers**

        restjson.use router, (req, res, next) ->
          # always send back contents of 'result' if available
          unless res.locals.result? then return next 'route'
          res.setHeader 'Expires','-1'
          res.send res.locals.result
          next()

        # default log successful transaction
        restjson.use (req, res, next) ->
          #req.forge.log?.info query:req.params.id,result:res.locals.result,
          # 'METHOD results for %s', req.record?.name
          next()

        # default 'catch-all' error handler
        restjson.use (err, req, res, next) ->
          console.error err
          res.status(500).send error: JSON.stringify err

        # TODO open up a socket.io connection stream for store updates

        console.info "restjson: binding forgery to /restjson".grey
        # should attach bp.json strict: true here
        # app.use bp.json string: true
        app.use "/restjson", restjson
        return router
