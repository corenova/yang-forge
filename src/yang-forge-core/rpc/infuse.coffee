# infuse - absorbs core(s) into current core

module.exports = (input, output, done) ->
  try
    console.warn 'infusing cores...'
    res = @parent.merge (input.get 'cores')
    output.set 'message', 'request processed successfully'
    output.set 'modules', res
    done()
  catch err
    done err
