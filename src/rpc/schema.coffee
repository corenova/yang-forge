# rpc schema - provides various schema operations and output formats

yang     = require 'yang-js'
yaml     = require 'js-yaml'
traverse = require 'traverse'
pretty   = require 'prettyjson'
treeify  = require 'treeify'
fs       = require 'fs'

module.exports = (input, resolve, reject) ->
  opts = input.options
  ys = switch
    when opts.eval? then yang.parse opts.eval
    else yang.require input.arguments[0]

  result = switch opts.format
    when 'json'   then JSON.stringify ys.toObject(), null, opts.space
    when 'yaml'   then yaml.dump ys.toObject(), lineWidth: -1
    when 'tree'   then treeify.asTree ys.toObject(), true
    when 'pretty' then pretty.render ys.toObject(), opts
    when 'yang'   then ys.toString()
    #when 'xml'    then js2xml 'schema', obj, prettyPrinting: indentString: '  '
    else reject new Error "unknown '#{opts.format}' format"

  return resolve result unless opts.output?
  fs.writeFile opts.output, result, 'utf8', (err) ->
    if err? then reject err
    else resolve "output saved to '#{opts.output}'"
