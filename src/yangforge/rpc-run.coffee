module.exports = (input, output, done) ->
  app = @parent
  features = input.get 'options'
  console.log "forgery firing up..."
  for name, arg of features when arg? and arg isnt false
    console.debug? "#{name} with #{arg}"
    features[name] = (app.resolve 'feature', name)?.run? this, features

  @invoke 'infuse', targets: (input.get 'arguments').map (e) -> source: e
  .then (res) =>
    modules = res.get 'modules'
    output.set "running with: " + (['yangforge'].concat modules...)
    done()
  .catch (err) -> done err
