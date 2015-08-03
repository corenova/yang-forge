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
        router = (require 'express').Router()
        router.all '*', (req, res, next) =>
          req.forge = this
          next()

### Top-level REST/JSON routing facilities

* Every request will be processed for authorization
* OPTIONS - provides info on available modules and other associated metadata

        router.route '/'
        .all (req, res, next) ->
          # XXX - verify req.user has permissions to operate on the forgery
          next()
        .options (req, res, next) ->
          res.locals.result =
            metadata: req.forge.constructor.info()
            modules: (for module in (req.forge.get 'modules')
              metadata: module.constructor.info()
              rpc: (for name, rpc of (module.meta 'rpc')
                name: name
                description: rpc.get 'description'
              ).reduce ((a,b) -> a[b.name] = b.description; a), {}
            ).reduce ((a,b) -> a[b.metadata.name] = b; a), {}
          next()
        .get  (req, res, next) -> res.locals.result = req.forge.serialize(); next()
        .post (req, res, next) ->
          # XXX - Enable creation of a new module into the target forge endpoint
          next()
        .copy (req, res, next) ->
          # XXX - generate JSON serialized copy of this forge
          next()

        router.param 'module', (req,res,next,module) ->
          self = req.forge.access module
          unless (self?.meta 'yang') is 'module' then next 'route'
          else req.module = self; next()

        router.param 'method', (req,res,next,method) ->
          console.assert req.module?,
            "cannot perform '#{method}' without containing module"
          req.rpc = req.module.meta "rpc.#{method}"
          if req.rpc? then next() else next 'route'

        router.param 'container', (req,res,next,container) ->
          self = req.module.access container
          unless (self?.meta 'yang') is 'container' then next 'route'
          else req.container = self; next()

### /:module routing endpoint

        router.route '/:module'
        .all (req, res, next) ->
          # XXX - verify req.user has permissions to operate on this module
          next()
        .options (req, res, next) ->
          res.locals.result =
            metadata: req.module.constructor.info()
            rpc: (for name, rpc of (req.module.meta 'rpc')
              name: name
              description: rpc.get 'description'
            ).reduce ((a,b) -> a[b.name] = b.description; a), {}
          next()
        .get (req, res, next) -> res.locals.result = req.module.serialize(); next()

### /:module/:method routing endpoint

        router.route '/:module/:method'
        .all (req, res, next) -> next()
        .options (req, res, next) ->
          res.locals.result =
            metadata: req.rpc.extract 'name', 'description', 'status'
            input:  req.rpc.reduce().input?.meta
            output: req.rpc.reduce().output?.meta
          next()
        .post (req, res, next) ->
          console.info "restjson: invoking rpc method '#{req.rpc.get 'name'}'".grey
          action = new req.rpc input: req.body, req.module
          action.invoke req.query
          .then  (result) -> res.locals.result = (action.get 'output'); next()
          .catch (err) ->
            console.error err
            next error

### /:module/* configuration tree routing endpoint

        subrouter = (require 'express').Router()
        subrouter.param 'subcontainer', (req,res,next,subcontainer) ->
          self = req.container?.access subcontainer
          req.container = self; next()

        subrouter.route '/'
        .get (req, res, next) -> res.locals.result = req.container.serialize(); next()

        # nested sub-routes for containers
        subrouter.use '/:subcontainer', subrouter

        router.use '/:module/:container', subrouter

### Default routing middleware handlers 

        # always send back contents of 'result' if available
        router.use (req, res, next) ->
          unless res.locals.result? then return next 'route'
          res.setHeader 'Expires','-1'
          res.send res.locals.result
          next()

        # default log successful transaction
        router.use (req, res, next) ->
          console.log "METHOD results..."
          #req.forge.log?.info query:req.params.id,result:res.locals.result, 'METHOD results for %s', req.record?.name
          next()

        # default 'catch-all' error handler
        router.use (err, req, res, next) ->
          console.error err
          res.status(500).send error: JSON.stringify err

        # TODO open up a socket.io connection stream for store updates

        console.info "restjson: binding forgery to /restjson".grey
        # should attach bp.json strict: true here
        # app.use bp.json string: true
        app.use "/restjson", router
        return router
