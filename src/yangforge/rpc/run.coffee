# run - conditionally loads module(s) into core and runs them
#
# CLI-only feature

module.exports = (input, output, done) ->
  core = @parent
  features = input.get 'options'
  for name, arg of features when arg? and arg isnt false
    console.debug? "#{name} with #{arg}"
    core.run name, arg
    #features[name] = (app.resolve 'feature', name)?.run? this, features

  res = core.origin.compose (input.get 'arguments')
  @invoke 'infuse', cores: res.dump()
  .then (res) =>
    modules = res.get 'modules'
    output.set "running with: " + (['yangforge'].concat modules...)
    done()
  .catch (err) -> done err
