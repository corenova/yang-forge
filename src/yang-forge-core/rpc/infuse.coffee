# infuse - absorbs core(s) into current core

module.exports = (input, output, done) ->
  try
    core = input.get 'core'
    return done() unless core?
    res = @parent.merge (input.get 'core')
    output.set 'message', 'request processed successfully'
    output.set 'modules', res
    done()
  catch err
    done err
