# infuse - loads core(s) into engine

module.exports = (input, output, done) ->
  app = @parent
  sources = input.get 'sources'
  sources = sources.concat ((input.get 'targets').map (e) -> e.source)...
  unless sources.length > 0
    output.set 'message', 'no operation since no sources(s) were specified'
    return done()

  app.import sources
  .then (res) =>
    promises = res.reduce ((a,b) -> a.concat b.save()...), []
    @invoke promises.map (p) -> (resolve) -> resolve p
  .then (modules) ->
    for model in modules
      #console.log "<infuse> absorbing a new model '#{model.name}' into running forge"
      app.attach model.name, model
    modules
  .then (modules) ->
    output.set 'message', 'request processed successfully'
    output.set 'modules', modules.map (x) -> x.name
    #console.log "<infuse> completed"
    done()
  .catch (err) -> done err
