# Auto documentation generation interface feature module

This feature add-on module enables generation of a web-based client
application based on the underlying [express](express.litcoffee) and
[restjson](restjson.litcoffee) feature add-ons to dynamically generate
user friendly documentation browsing capability.

## Source Code

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
