# yang-forge - load and build cores

module.exports = (->
  @set basedir: __dirname
  @include '..'
  @link '.'
  @load 'yang-forge-core'
).call (require 'yang-cc')
