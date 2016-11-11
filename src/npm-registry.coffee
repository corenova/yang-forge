co = require 'co'
npm = require 'npm'
thunkify = require 'thunkify'
load = thunkify npm.load
view = thunkify npm.view

module.exports =
  view: co.wrap (pkgs...) ->
    yield load loglevel: 'silent', loaded: false
    info = yield pkgs.map (pkg) -> view pkg
    res = info.reduce ((a,b) ->
      a.push meta for ver, meta of b[0]
      return a
    ), []
    return res
