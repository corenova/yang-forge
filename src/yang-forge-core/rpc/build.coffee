# rpc build - generates the core composition

ycc  = require 'yang-cc'
fs   = require 'fs'
#zlib = require 'zlib'

module.exports = (input, output, done) ->
  args = input.get 'arguments'
  opts = input.get 'options'

  unless args.length > 0
    # should handle this case differently?
    return done()

  ycc = new ycc.Composer ycc # make a fresh copy
  ycc.set basedir: process.cwd()
  ycc.include opts.include
  ycc.link opts.link

  core = ycc.compose args
  console.debug? core

  unless opts.output?
    output.set core.dump()
    return done()

  fs.writeFile opts.output, core.dump(), 'utf8', (err) ->
    output.set "output saved to '#{opts.output}'"
    if err? then done err else done()
