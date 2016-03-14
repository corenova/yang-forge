# run - conditionally loads core(s) into engine and runs them

module.exports = (input, output, done) ->
  core = @parent
  features = input.get 'options'
  for name, arg of features when arg? and arg isnt false
    console.debug? "#{name} with #{arg}"
    features[name] = (app.resolve 'feature', name)?.run? this, features

  @invoke 'infuse', targets: (input.get 'arguments').map (e) -> source: e
  .then (res) =>
    modules = res.get 'modules'
    output.set "running with: " + (['yangforge'].concat modules...)
    done()
  .catch (err) -> done err
