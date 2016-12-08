require 'yang-js'
debug = require('debug')('yang-forge:fs') if process.env.DEBUG?
co = require 'co'
fs = require 'co-fs'
path = require 'path'
thunkify = require 'thunkify'
mkdirp = thunkify require 'mkdirp'

module.exports = require('../schema/file-system.yang').bind {

  'grouping(file)/read': ->
    { name, store } = @get('..')
    debug? "[read(#{name})] retrieving from #{store}"
    @output = @in(store).in('read').do name

  # TODO: this should perform implicit 'extract' if @input.file is specified
  'grouping(archive)/read': (target) ->
    { name, store, directory } = @get('..')
    name = path.join name, target if target?
    if store?
      debug? "[read(#{name})] retrieving from #{store}"      
      @output = @in(store).in('read').do name
    else
      name = path.resolve directory, name
      @output = co -> data: yield fs.readFile name, 'utf-8'

  'grouping(archive)/tag': ->
    { files } = @input
    for file in @get('../file') when file.name in files
      file.tagged = true
      files.splice(files.indexOf(file.name), 1)
      break unless files.length
    if files.length
      @throw "unable to tag #{files.length} files: #{files}"

  'grouping(archive)/extract': ->
    { dest, filter } = @input
    { name, store, directory } = archive = @get('..')
    files = archive.file
    if filter?
      files = files?.filter (file) ->
        for k, v of filter
          return false if file[k] isnt v 
        return true
    debug? "[extract(#{name})] #{files.length} files to #{dest}"
    @output = co =>
      yield mkdirp dest
      yield files.map co.wrap (file) ->
        yield mkdirp path.join(dest, path.dirname file.name)
        res = yield archive.read file.name
        yield fs.writeFile path.join(dest, file.name), res.data
        return file.name
  
  'grouping(archive)/files-count': ->
    @content ?= @get('../file')?.length
    
  'grouping(archive)/files-size': ->
    @content ?= @get('../file')?.reduce ((size, i) -> size += i.size), 0

  'grouping(archive)/file/store': ->
    archive = @in('../../..')
    @content = "#{archive.path}"

}
