Forge = require '../yangforge'

module.exports = Forge.Interface
  name: 'restjson'
  description: 'REST/JSON web services interface generator'
  needs: [ 'express' ]
  generator: (app) ->
    console.log "generating REST/JSON interface..."
    forge = this
    router = (require 'express').Router()
    router.all '*', (req, res, next) ->
      req.forge = forge
      next()

    router.route '/'
    .all (req, res, next) ->
      # XXX - verify req.user has permissions to operate on the DataStorm
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
      parent = req.container ? req.module
      console.assert parent?,
        "cannot access without parent containing entity"
      self = parent.access container
      req.container = self; next()
      return
      
      unless self instanceof Forge.Object then next 'route'
      else req.container = self; next()

    router.param 'method', (req,res,next,method) ->
      console.assert req.module?,
        "cannot perform '#{method}' without containing module"
      req.method = req.module.invoke method, req.query, req.body
      if req.method? then next() else next 'route'

    # handle the top-level module endpoint
    router.route '/:module'
    .all (req, res, next) ->
      # XXX - verify req.user has permissions to operate on this module
      next()
    .get (req, res, next) -> res.locals.result = req.module.serialize(); next()
      
    # handle sub-module endpoints
    router.route '/:module/:container'
    .all (req, res, next) -> next()
    .get (req, res, next) -> res.locals.result = req.container.serialize(); next()

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
      res.status(500).send error: err

    # TODO open up a socket.io connection stream for store updates

    console.log "binding forge to /#{forge.meta 'name'}"
    app.use "/#{forge.meta 'name'}", router
    return router

    # @include = (module) =>
    #   return unless Forge.instanceof module

    #   storm = new module
    #   # need to handle auditor and authorizer
    #   # need to handle store.initialize type call
    #   @use (module.get 'name'), (createStormRouter storm)

    #   for submodule in (module.get 'stores')
    #     substorm = new submodule
    #     @use (submodule.get 'name'), (createStormRouter substorm)

    
    
    
