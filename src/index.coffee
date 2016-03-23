# yangforge - load and build cores

module.exports = (->
  @set basedir: __dirname
  @include '..'
  @link '../lib/feature'
  @compose 'yangforge'
).call (require 'yang-cc')
