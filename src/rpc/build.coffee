

module.exports = (input, resolve, reject) ->
  args = input.arguments
  opts = input.options

  unless args.length > 0
    # should handle this case differently?
    return done()

  ycc = # make a fresh copy
    (new ycc.Composer ycc)
    .set basedir: process.cwd()
    .include opts.include
    .link opts.link

  (ycc.load args).dump meta: opts
  .then (res) ->
    unless opts.output?
      output.set res
      return done()

    fs.writeFile opts.output, res, 'utf8', (err) ->
      output.set "output saved to '#{opts.output}'"
      if err? then done err else done()
  .catch (err) -> done err

  
