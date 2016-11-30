debug = require('debug')('yang-forge:remote-registry') if process.env.DEBUG?
co = require 'co'
fs = require 'co-fs'
path = require 'path'
npm = require 'npm'
gunzip = require 'gunzip-maybe'
tar = require 'tar-fs'
request = require 'superagent'
thunkify = require 'thunkify'
load = thunkify npm.load
view = thunkify npm.view

fetching = {}

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

  stat: co.wrap (names...) ->
    return {} unless names.length
    api = "https://api.npmjs.org/downloads/point"
    output = {}
    output[names[key]] = names[key] for key in [0...names.length]
    names = (value for key, value of output)
    target = names.join(',')
    debug? "[stat] collecting download stats for #{target}"
    [ day, week, month ] = yield [
      request.get("#{api}/last-day/#{target}")
      request.get("#{api}/last-week/#{target}")
      request.get("#{api}/last-month/#{target}")
    ]
    for name in names
      if names.length > 1
        output[name] =
          'last-day': day.body[name].downloads
          'last-week': week.body[name].downloads
          'last-month': month.body[name].downloads
      else
        output[name] =
          'last-day': day.body.downloads
          'last-week': week.body.downloads
          'last-month': month.body.downloads
    return output
    
  fetch: co.wrap (to='/tmp', pkgs...) ->
    yield pkgs.map (pkg) ->
      { shasum, tarball } = pkg.dist
      return fetching[shasum] if fetching.hasOwnProperty(shasum)

      pkgtag = "#{pkg.name}@#{pkg.version}"
      target = path.resolve(to, shasum)
      cached = yield fs.exists(target)
      files = []
      extract = tar.extract target, {
        map: (header) ->
          return header if cached
          components = path.normalize(header.name).split(path.sep)
          components.shift()
          header.name = path.join components...
          return header
        ignore: (name, header) ->
          return true if header.type isnt 'file'
          copy = Object.assign {}, header
          copy.mtime = header.mtime.toJSON()
          files.push copy
          debug? "[fetch] extract #{header.name} from #{pkgtag}"
          return cached
      }
      if cached
        debug? "[fetch] local #{pkgtag} from #{target}"
        stream = tar.pack target
      else
        debug? "[fetch] remote #{pkgtag} from #{tarball}"
        stream = request.get(tarball).pipe(gunzip())
      stream.pipe extract
      return fetching[shasum] = new Promise (resolve, reject) ->
        extract.on 'error', (err) -> reject err
        extract.on 'finish', ->
          debug? "[fetch] extracted #{files.length} files from #{pkgtag}"
          resolve
            id: shasum
            file: files
