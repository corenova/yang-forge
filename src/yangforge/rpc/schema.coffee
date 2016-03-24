fs = require 'fs'

module.exports = (input, output, done) ->
  core = @parent

  options = input.get 'options'
  schemas = (input.get 'arguments').map (x) ->
    if /^[\-\w\.]+$/.test x then fs.readFileSync x, 'utf-8'
    else x
  schemas.push options.eval if options.eval?

  schema = schemas.pop()
  result = switch
    when options.compile    then core.origin.compile schema
    when options.preprocess then (core.origin.preprocess schema).schema
    else core.origin.parse schema

  result = (core.dump result, options)
  unless options.output?
    output.set result
    return done()

  output.set "output saved to '#{options.output}'"
  fs.writeFile options.output, result, 'utf8', (err) ->
    if err? then done err else done()
