debug = require('debug')('yang-forge:remote-registry') if process.env.DEBUG?
co = require 'co'
fs = require 'fs'
path = require 'path'
npm = require 'npm'
targz = require 'tar.gz'
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
      filename = path.resolve(to, shasum)
      cached = fs.existsSync(filename)
      if cached
        debug? "[fetch] local #{pkg.name}@#{pkg.version} from #{filename}"
        stream = fs.createReadStream(filename)
      else
        debug? "[fetch] remote #{pkg.name}@#{pkg.version} from #{tarball}"
        stream = request.get(tarball)

      return fetching[shasum] = new Promise (resolve, reject) ->
        parse = targz().createParseStream()
        contents = []
        parse.on 'entry', (entry) -> contents.push entry.path
        parse.on 'end', ->
          if cached
            bytes = stream.bytesRead
          else
            bytes = stream.response.header['content-length']
          resolve
            id: shasum
            bytes: bytes
            contents: contents
        parse.on 'error', (err) ->
          console.error "parse error on #{filename}"
          reject err
        stream.pipe(parse)
        stream.pipe(fs.createWriteStream filename) unless cached
        
