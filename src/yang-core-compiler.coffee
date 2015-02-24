###*
# @module YangCoreCompiler
# @main YangCoreCompiler
###
class YangCoreCompiler extends (require 'meta-class')
  @set
    module:
      extension: '0..n'
    extension:
      resolver: (arg, params) -> @merge arg, params; null
      argument: '0..1'
      description: '0..1'
      reference: '0..1'
      status: '0..1'
      pre: '0..1'      # not YANG spec compliant
      sub: '0..1'      # not YANG spec compliant
    argument: 'yin-element': '0..1'
    description: 'argument text': 'yin-element': true
    reference: 'argument text': 'yin-element': true
    status: argument: 'value'
    value: argument: 'value'

    # custom built-in language extension
    resolver: argument: 'function'
    sub:
      argument: 'keyword',
      resolver: (arg, params) -> params?.value
      value: '0..1'
    'yang-version': argument: 'value'
    'yin-element': argument: 'value'

  @parser:
    text: (require 'yang-parser').parse
    json: (obj) ->
      statements = []
      for key, val of obj
        [ kw, arg ] = key.split ' '
        [ prf, kw ] = kw.split ':'
        unless kw?
          kw = prf
          prf = ''
        substmts = undefined
        switch
          when val instanceof Function then arg ?= val
          when val not instanceof Object then arg ?= val
          else
            substmts = @json val
            unless substmts instanceof Array
              substmts = [ substmts ]
        statements.push prf: prf, kw: kw, arg: arg, substmts: substmts
      switch
        when statements.length > 1 then statements
        when statements.length is 1 then statements[0]
        else undefined
    source: (func) -> ((require 'tosource') func) if func instanceof Function

  @compile: (schema, opts={}) ->
    output = @compileStatement switch
      when typeof schema is 'string' then @parser.text schema
      when typeof schema is 'object' then @parser.json schema
      else null

    output?.value?.extend? this if opts.compiler is true
    output?.value

  ###*
  # `compileStatement` performs recursive compilation of passed in
  # statement and sub-statements
  ###
  @compileStatement: (statement) ->
    return unless statement? and statement instanceof Object

    normalize = (statement) -> ([ statement.prf, statement.kw ].filter (e) -> e? and !!e).join ':'
    keyword = normalize statement
    target = (@get keyword)

    unless target?
      console.log "unrecognized keyword extension '#{keyword}', skipping..."
      return null
    unless statement.substmts?.length > 0
      # console.log "no substatements for '#{keyword}'"
      # console.log statement
      return name: statement.kw, value: statement.arg

    # TODO - add enforcement for cardinality specification '0..1' or '0..n'
    results = (@compileStatement stmt for stmt in statement.substmts when switch
      when not (meta = @get keyword)?
        console.log "unable to find metadata for #{keyword}"
        false
      when not meta.hasOwnProperty(normalize stmt)
        console.log "#{keyword} does not have sub statement declared for #{normalize stmt}"
        false
      else true
    )
    params = (results.filter (e) -> e? and e.value?).reduce ((a,b) -> a[b.name] = b.value; a), {}
    value = switch
      when target.resolver instanceof Function
        target.resolver.call this, statement.arg, params, target
      else
        class extends (require 'meta-class')

    value?.set? yang: keyword
    value?.extend? params

    (@set "#{statement.kw}:#{statement.arg}", value) if statement.arg? and value?.set?

    return name: (statement.arg ? statement.kw), value: value

module.exports = YangCoreCompiler
