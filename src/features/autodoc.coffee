Forge = require '../yangforge'

module.exports = Forge.Interface
  name: 'autodoc'
  description: 'Automated schema driven documentation generator'
  generator: ->
    # kicks off after all features running
    @on 'running', (runners) ->
      for feature, instance of runners
        switch feature
          when 'restjson'
            console.info "enabling autodoc on restjson"
