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

    router.route '/'
    .all (req, res, next) ->
      # XXX - verify req.user has permissions to operate on the forgery
      next()
    .get (req, res, next) ->
      res.locals.result = req.forge.serialize()
      next()
    .post (req, res, next) ->
      # XXX - Enable creation of a new collection into the target forge
      next()
    .copy (req, res, next) ->
      # XXX - generate JSON serialized copy of this forge
      next()

    router.param 'module', (req,res,next,module) ->
      self = req.forge.access module
      unless (self?.meta 'yang') is 'module' then next 'route'
      else req.module = self; next()

    router.param 'container', (req,res,next,container) ->
      self = req.module.access container
      unless (self?.meta 'yang') is 'container' then next 'route'
      else req.container = self; next()

    router.param 'method', (req,res,next,method) ->
      console.assert req.module?,
        "cannot perform '#{method}' without containing module"
      if method of req.module.methods
        req.method = req.module.invoke method, req.body, req.query
        next()
      else next 'route'

    # SUB ROUTER
    subrouter = (require 'express').Router()
    subrouter.param 'subcontainer', (req,res,next,subcontainer) ->
      self = req.container?.access subcontainer
      req.container = self; next()

    subrouter.route '/'
    .get (req, res, next) -> res.locals.result = req.container.serialize(); next()

    # nested sub-routes for containers
    subrouter.use '/:subcontainer', subrouter
        
    # handle the top-level module endpoint
    router.route '/:module'
    .all (req, res, next) ->
      # XXX - verify req.user has permissions to operate on this module
      next()
    .get (req, res, next) -> res.locals.result = req.module.serialize(); next()

    router.use '/:module/:container', subrouter

    router.route '/:module/:method'
    .all (req, res, next) -> next()
    .post (req, res, next) ->
      req.method.then (
        (response) -> res.locals.result = response; next()
        (error)    -> next error
      )

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
    app.use "/restjson", router
    return router
