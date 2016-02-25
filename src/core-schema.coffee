yaml = require 'js-yaml'

module.exports = yaml.Schema.create [

  new yaml.Type '!xform',
    kind: 'mapping'
    resolve:   (data={}) -> true
    construct: (data) -> data

]

