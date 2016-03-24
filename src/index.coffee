# yangforge - load and build cores

module.exports = (->
  @set basedir: __dirname
  @include '..'
  @link './yangforge'
  @compose 'yangforge'
).call (require 'yang-cc')
