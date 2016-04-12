# inspect - grabs info about a core from the local filesystem
ycc = require 'yang-cc'
fs  = require 'fs'

module.exports = (input, output, done) ->
  arg = (input.get 'arguments').pop()
  opts = input.get 'options'

  schema = fs.readFileSync arg, 'utf-8'
  { map } = ycc.preprocess schema

  # TODO: improve the quality of this output
  output.set map
  done()
