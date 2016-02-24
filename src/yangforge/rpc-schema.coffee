fs = require 'fs'

module.exports = (input, output, done) ->
  app = @parent
  options = input.get 'options'
  schema = (input.get 'arguments')[0]
  schema = options.eval if options.eval?
  result = switch
    when options.load
      source = app.load "!yang #{schema}", async: false
      for name, model of source.properties
        console.info "absorbing a new model '#{name}' into running forge"
        app.attach name, model
      source.constructor
    when options.compile then app.compile "!yang #{schema}"
    when options.preprocess then (app.preprocess "!yang #{schema}").schema
    else app.parse "!yang #{schema}"
  result = (app.render result, options)
  unless options.output?
    output.set result
    return done()

  output.set "output saved to '#{options.output}'"
  fs.writeFile options.output, result, 'utf8', (err) ->
    if err? then done err else done()
