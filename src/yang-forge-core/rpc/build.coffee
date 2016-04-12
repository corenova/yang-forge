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

  ycc = # make a fresh copy
    (new ycc.Composer ycc)
    .set basedir: process.cwd()
    .include opts.include
    .link opts.link

  res = (ycc.load args).dump meta: opts
  unless opts.output?
    output.set res
    return done()

  fs.writeFile opts.output, res, 'utf8', (err) ->
    output.set "output saved to '#{opts.output}'"
    if err? then done err else done()
