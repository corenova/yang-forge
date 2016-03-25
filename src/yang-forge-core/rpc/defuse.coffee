module.exports = (input, output, done) ->
  core = @parent
  for name in input.get 'names'
    core.detach name
  output.set 'message', 'OK'
  done()
