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

  schemas = input.get 'arguments'
  unless schemas.length > 0
    output.set "running yang-forge-core"
    return done()

  res = core.origin.compose schemas
  @invoke 'infuse', cores: res.dump()
  .then (res) =>
    modules = res.get 'modules'
    output.set "running with: " + (['yangforge'].concat modules...)
    done()
  .catch (err) -> done err
