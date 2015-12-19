# YANG-ROUTER feature-helper module

express = require 'express'

sourceRouter = (->
  @route '/'
  .all (req, res, next) ->
    if (req.target?.meta? 'synth') is 'source'
      console.log "source router: #{req.originalUrl}"
      next()
    else next 'route'
  .options (req, res, next) ->
    res.send
      REPORT:
        description: 'get detailed information about this source'
      GET:
        description: 'get serialized output for this source'
      PUT:
        description: 'update configuration for this source'
      COPY:
        description: 'get a copy of this source for cloning it elsewhere'
  .report (req, res, next) -> 
    res.locals.result = req.target.info(); next()
  .copy (req, res, next) ->
    res.locals.result = req.target.export(); next()

  return this
).call express.Router()

storeRouter = (->
  @route '/'
  .all (req, res, next) ->
    if (req.target?.meta? 'synth') is 'store'
      console.log "store router: #{req.originalUrl}"
      next()
    else next 'route'
  .report (req, res, next) ->
    res.locals.result = req.target.parent.info()
    next()

  return this
).call express.Router()

modelRouter = (->
  @route '/'
  .all (req, res, next) ->
    if (req.target?.meta? 'synth') in [ 'store', 'model' ]
      console.log "model router: #{req.originalUrl}"
      next()
    else next 'route'
  .put (req, res, next) ->
    (req.target.set req.body).save()
    .then (result) ->
      res.locals.result = req.target.serialize();
      next()
    .catch (err) ->
      req.target.rollback()
      next err

  @param 'action', (req, res, next, action) ->
    if req.target.methods?[action]? then next() else next 'route'

  @route '/:action'
  .options (req, res, next) ->
    method = req.target.methods[req.params.action]
    input  = method.input.extract()
    output = method.output.extract()
    # need to do something better...
    delete input?.uses
    delete input?.typedef
    delete input?.bindings
    delete output?.uses
    delete output?.typedef
    delete output?.bindings
    res.send
      POST:
        description: method.params.description
        status:      method.params.status
        reference:   method.params.reference
        input:  input
        output: output
  .post (req, res, next) ->
    console.info "restjson: invoking rpc operation '#{req.params.action}'".grey
    req.target.invoke req.params.action, req.body
      .then  (output) -> res.locals.result = output.get(); next()
      .catch (err) -> next err
  return this
).call express.Router()

objectRouter = (->
  @route '/'
  .all (req, res, next) ->
    if (req.target?.meta? 'synth') is 'object'
      console.log "object router: #{req.originalUrl}"
      next()
    else next 'route'
  .put (req, res, next) ->
    req.target.set req.body
    model = req.target.seek synth: (v) -> v in [ 'store', 'model' ]
    model.save()
    .then (result) ->
      res.locals.result = req.target.serialize();
      next()
    .catch (err) ->
      req.target.rollback()
      next err

  # Add any special logic for handling 'container' here
  return this
).call express.Router()

listRouter = (->
  @route '/'
  .all (req, res, next) ->
    if (req.target?.meta? 'synth') is 'list'
      console.log "list router: #{req.originalUrl}"
      next()
    else next 'route'
  .post (req, res, next) ->
    return next "cannot add a new entry without supplying data" unless Object.keys(req.body).length
    items = switch
      when req.body instanceof Array then req.target.push req.body...
      else req.target.push req.body
    model = req.target.seek synth: (v) -> v in [ 'store', 'model' ]
    model.save()
    .then (result) ->
      res.locals.result = req.target.serialize()
      next()
    .catch (err) ->
      model.rollback()
      next err

  @delete '/:key', (req, res, next) ->
    return next 'route' unless req.target.remove?
    
    req.target.remove req.params.key
    model = req.target.seek synth: (v) -> v in [ 'store', 'model' ]
    model.save()
    .then (result) ->
      res.locals.result = result.serialize()
      next()
    .catch (err) ->
      model.rollback()
      next err

  return this
).call express.Router()

module.exports = ((target) ->
  @all '*', (req, res, next) ->
    req.target ?= target
    next()

  @param 'target', (req, res, next, target) ->
    match = req.target.access? target
    if match? then req.target = match; next() else next 'route'

  @get '/', (req, res, next) ->
    res.locals.result = req.target.serialize()
    next()

  @use sourceRouter, storeRouter, modelRouter, objectRouter, listRouter
  # nested loop back to self to process additional sub-routes
  @use '/:target', this
  
  return this
).bind express.Router()
