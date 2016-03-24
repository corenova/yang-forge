# yang-forge - load and build cores

module.exports = (->
  @set basedir: __dirname
  @include '..'
  @link '.'
  @compose 'yang-forge-core'
).call (require 'yang-cc')
