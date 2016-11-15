debug = require('debug')('yang-forge:npm-registry') if process.env.DEBUG?
co = require 'co'
fs = require 'fs'
path = require 'path'
npm = require 'npm'
targz = require 'tar.gz'
request = require 'superagent'
thunkify = require 'thunkify'
load = thunkify npm.load
view = thunkify npm.view

module.exports =
  view: co.wrap (names...) ->
    debug? "[view] npm load"
    yield load loglevel: 'silent', loaded: false
    debug? "[view] npm view #{names}"
    info = yield names.map (name) -> view name
    res = info.reduce ((a,b) ->
      a.push meta for ver, meta of b[0]
      return a
    ), []
    return res
  cache: co.wrap (to='/tmp', pkgs...) ->
    yield pkgs.map (pkg) ->
      filename = path.resolve(to, pkg.dist.shasum)
      unless pkg.dist.cached
        debug? "[cache] fetch remote #{pkg.dist.tarball}"
        stream = fs.createWriteStream filename
        res = request.get(pkg.dist.tarball)
        res.pipe(stream)
      else
        debug? "[cache] fetch local #{filename}"
        res = fs.createReadStream(filename)
      new Promise (resolve, reject) ->
        parse = targz().createParseStream()
        contents = []
        parse.on 'entry', (entry) -> contents.push entry.path
        parse.on 'end', ->
          resolve
            id: pkg.dist.shasum
            bytes: res.bytesRead
            contents: contents
        res.pipe(parse)
