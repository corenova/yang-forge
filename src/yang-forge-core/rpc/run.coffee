# run - build/infuse module(s) into core and runs them
#
# CLI-only feature

module.exports = (input, output, done) ->
  features = input.get 'options'

  @invoke 'build', input.get()
  .then (res) => @invoke 'infuse', core: res.get()
  .then (res) =>
    core = @parent
    for name, arg of features when arg? and arg isnt false
      console.debug? "#{name} with #{arg}"
      core.run name, arg
    output.set "running with: " + Object.keys core.properties
    done()
  .catch (err) -> done err
