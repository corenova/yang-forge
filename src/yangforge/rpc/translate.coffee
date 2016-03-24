module.exports =  (input, output, done) ->
  app = @parent
  data = (input.get 'arguments')[0]
  options = input.get 'options'

  data = app.parse "!json #{data}"
  output.set app.set(data).render app.get(), options
  # output.set app.fork ->
  #   @set data
  #   @render @get(), options

  if options.output?
    fs = require 'fs'
    fs.writeFile options.output, output.get(), 'utf8', (err) ->
      if err? then done err else done()
  else done()
