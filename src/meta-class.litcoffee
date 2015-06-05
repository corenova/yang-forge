# meta-class 

    class Meta
      @__meta__: bindings: {}
      @__version__: 3

## general utility helper functions

      assert = require 'assert'
      @instanceof: (obj) ->  obj?.instanceof is arguments.callee
      @copy: (dest, src) ->
        for p of src
          if src[p]?.constructor is Object
            dest[p] ?= {}
            arguments.callee dest[p], src[p]
          else dest[p] = src[p]
        return dest
      @objectify: (key, val) ->
        return key if key instanceof Object
        composite = ((key?.split '.').filter (e) -> !!e) ? []
        unless composite.length
          return val ? {}
          
        obj = root = {}
        while (k = composite.shift())
          last = r: root, k: k
          root = root[k] = {}
        last.r[last.k] = val
        obj

## meta data operators (on this.__meta__)

The following `get/extract/match` provide meta data retrieval mechanisms.
 
      @get: (key) ->
        return unless key? and typeof key is 'string'
        root = @__meta__ ? this
        composite = (key?.split '.').filter (e) -> !!e
        root = root?[key] while (key = composite.shift())
        root
      @extract: (keys...) ->
        res = {}
        Meta.copy res, Meta.objectify key, @get key for key in keys
        res
      @match: (regex) ->
        root = @__meta__ ? this
        obj = {}
        obj[k] = v for k, v of root when (k.match regex)
        obj

The following `set/merge` provide meta data update mechanisms.
        
      @set: (key, val) ->
        obj = Meta.objectify key, val
        @__meta__ = Meta.copy (Meta.copy {}, @__meta__), obj
        this
      @merge: (key, obj) ->
        unless typeof key is 'string'
          (@merge k, v) for k, v of (key.__meta__ ? key)
          return this
        target = @get key
        switch
          when not target? then @set key, obj
          when (Meta.instanceof target) and (Meta.instanceof obj)
            target.merge obj
          when target instanceof Function and obj instanceof Function
            target.mixin? obj
          when target instanceof Array and obj instanceof Array
            Array.prototype.push.apply target, obj
          when target instanceof Object and obj instanceof Object
            target[k] = v for k, v of obj
          else
            assert typeof target is typeof obj,
              "cannot perform 'merge' for #{key} with existing value type conflicting with passed-in value"
            @set key, obj
        this

The `bind` function associates the passed in key/object into the meta
class so that when this class object is instantiated, all the bound
objects are actualized during construction.  It protects the key under
question so that the binding can only take place once for a given key.
        
      @bind: (key, obj) -> unless (@get "bindings.#{key}")? then @set "bindings.#{key}", obj
        
## class object operators (on this)

      @configure: (f) -> f?.call? this; this
      @extend: (obj) ->
        @[k] = v for k, v of obj when k isnt '__super__' and k not in Object.keys Meta
        this
      @include: (obj) ->
        @::[k] = v for k, v of obj when k isnt 'constructor' and k not in Object.keys Meta.prototype
        this

The `mixin` convenience function essentially fuses the target class
obj(s) into itself.

      @mixin: (objs...) ->
        for obj in objs when obj instanceof Object
          @extend obj
          @include obj.prototype
          continue unless Meta.instanceof obj
          # when mixing in another Meta object, merge the 'bindings'
          # as well
          @merge obj.extract 'bindings'
        this

## meta class instance prototypes

      constructor: (@value={}) ->
        assert @value instanceof Object, "invalid input value for meta class construction"
        (@attach k, v) for k, v of (@constructor.get 'bindings')

      attach: (key, val) -> switch
        when (Meta.instanceof val)
          @properties ?= {}
          @properties[key] = new val @value[key]
          @isContainer = true
        when val instanceof Function
          @methods ?= {}
          @methods[key] = val
        when val?.constructor is Object
          (@attach k, v) for k,v of val
        else
          @statics ?= {}
          @statics[key] = val        

      fork: (f) -> f?.call? (new @constructor @get())
      extract: @extract

      getProperty: (key) ->
        return @properties[key]
        
        [ key, rest... ] = ((key?.split? '.')?.filter (e) -> !!e) ? []
        return unless key? and typeof key is 'string'
        prop = @properties[key]
        switch
          when rest.length is 0 then prop
          else prop?.getProperty? (rest.join '.')

      get: (key) ->
        [ key, rest... ] = ((key?.split? '.')?.filter (e) -> !!e) ? []
        switch
          when @isContainer and key? then (@getProperty key)?.get (rest.join '.')
          when @isContainer then @value[k] = v.get() for k, v of @properties; @value
          when key? then rest.unshift key; Meta.get.call @value, rest.join '.'
          else @value
            
      set: (key, val) ->
        key = val unless !!key
        if @isContainer
          switch
            when typeof key is 'string'
              [ key, rest... ] = ((key?.split? '.')?.filter (e) -> !!e) ? []
              (@getProperty key)?.set (rest.join '.'), val
            when key instanceof Object
              @set k, v for k, v of key
        else
          key ?= {}
          Meta.copy @value, (Meta.objectify key, val)
        this

      invoke: (name, args...) ->
        method = @methods?[name]
        assert method instanceof Function,
          "cannot invoke undefined '#{name}' method"
        method.apply this, args        
        
    module.exports = Meta
