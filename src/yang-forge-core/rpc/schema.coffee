# rpc schema - provides various schema operations and output formats

ycc      = require 'yang-cc'
yaml     = require 'js-yaml'
traverse = require 'traverse'
pretty   = require 'prettyjson'
treeify  = require 'treeify'
fs       = require 'fs'

module.exports = (input, output, done) ->
  args = input.get 'arguments'
  opts = input.get 'options'

  ycc = new ycc.Composer ycc # make a fresh copy
  ycc.set basedir: process.cwd()
  ycc.include opts.include
  ycc.link opts.link

  schemas = args.map (x) ->
    if /^[\-\w\.]+$/.test x then fs.readFileSync x, 'utf-8'
    else x
  schemas.push opts.eval if opts.eval?

  schema = schemas.pop()
  obj = switch
    when opts.compile    then ycc.compile schema
    else (ycc.preprocess schema).schema

  obj = (traverse obj).map (x) -> switch
    when x instanceof Function and x.extract?
      o = meta: x.extract()
      delete o.meta.bindings
      @update ycc.copy o, x.get 'bindings'
    when x instanceof Function and opts.format in ['json','pretty']
      if x.func instanceof Function
        @update x.func.toString()
      else
        @update x.toString()

  result = switch opts.format
    when 'json'   then JSON.stringify obj, null, opts.space
    when 'yaml'   then yaml.dump obj, lineWidth: -1
    when 'tree'   then treeify.asTree obj, true
    when 'pretty' then pretty.render obj, opts
    when 'yang'   then ycc.dump obj
    #when 'xml'    then js2xml 'schema', obj, prettyPrinting: indentString: '  '
    else obj

  result = switch opts.encoding
    when 'base64' then (new Buffer result).toString 'base64'
    else result

  unless opts.output?
    output.set result
    return done()

  output.set "output saved to '#{opts.output}'"
  fs.writeFile opts.output, result, 'utf8', (err) ->
    if err? then done err else done()
