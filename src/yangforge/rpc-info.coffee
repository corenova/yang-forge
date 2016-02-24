module.exports = (input, output, done) ->
  app = @parent
  target = (input.get 'arguments')[0]
  target ?= app
  app.import target
  .then (res) ->
    output.set res.info? (input.get 'options')
    done()
  .catch (err) -> done err
