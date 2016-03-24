module.exports = (input, output, done) ->
  app = @parent
  for name in input.get 'names'
    app.detach name
  output.set 'message', 'OK'
  done()
