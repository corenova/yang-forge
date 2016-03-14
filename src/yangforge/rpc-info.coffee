# info - grabs info about a core from the linked registry

module.exports = (input, output, done) ->
  core = @parent
  target = (input.get 'arguments')[0]
  target ?= '!core ./'
  done "not supported yet"

  # core.engine.fetch target

  # app.import target
  # .then (res) ->
  #   output.set res.info? (input.get 'options')
  #   done()
  # .catch (err) -> done err
