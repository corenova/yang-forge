browserify = require 'browserify'
zlib = require 'zlib'
fs = require 'fs'

module.exports = (input, output, done) ->
  app = @parent
  target = (input.get 'arguments')[0]
  options = input.get 'options'

  # unless target? or target is directory
  # 1. retrieve package.json
  # 1a. if has 'dependencies' then need to issue 'npm install' do it via API?
  # 2. retrieve package.yaml
  # 3. res = browserify package
  # 4. treat target as !yfx res

  return done "must specify target input file to build" unless target?

  app.import target
  .then (res) ->
    result = res.constructor.toSource format: 'yaml'
    if options.gzip
      console.log 'skip zlib'
      #result = zlib.deflate result

    unless options.output?
      output.set result
      return done()

    fs.writeFile options.output, result, 'utf8', (err) ->
      output.set "output saved to '#{options.output}'"
      if err? then done err else done()
  .catch (err) -> done err
