# YANG comlex-types Specifications

# The YANG complex-types module provides additional language
# extensions according to [RFC
# 6095](http://tools.ietf.org/html/rfc6095). These extensions provide
# mechanisms to manage the `complex-type` schema definitions which
# essentially allows a given YANG data schema module to describe more
# than one data models and to build relationships between the data
# models.

complex-types:
  extension:
    complex-type:
      abstract:      0..1
      container:     0..n
      description:   0..1
      extends:       0..1
      grouping:      0..n
      if-feature:    0..n
      key:           0..1
      instance:      0..n
      instance-list: 0..n
      leaf:          0..n
      leaf-list:     0..n
      reference:     0..1
      refine:        0..n
      uses:          0..n
      preprocess: !coffee/function |
        (arg, params, ctx) ->
          synth = @resolve 'feature', 'synthesizer'
          @define 'complex-type', arg, switch
            when params.extends?
              ctype = params.extends
              delete params.extends
              delete params.key if (ctype.get 'key')?
              (synth ctype) params, -> @set name: arg
            else 
              synth.Model params, -> @set name: arg
      construct: !coffee/function |
        (arg, params, children) ->
          ct = (@resolve 'complex-type', arg)
          if children.ctype?
            ct.bind (children.ctype.get 'bindings')
            delete children.ctype
          ct.bind children
          for target, changes of params.refine
            target = target.replace '/','.'
            ct.rebind target, (prev) -> prev.merge changes
          null

    abstract:

    extends:
      description: 0..1
      reference:   0..1
      status:      0..1
      preprocess: !coffee/function |
        (arg, params, ctx) ->
          ctx.extends = @resolve 'complex-type', arg
          unless ctx.extends?
            throw @error "unable to resolve dependent complex-type '#{arg}'", 'extends'
      construct:  !coffee/function |
        (arg, params, children, ctx) ->
          ctx.ctype = @resolve 'complex-type', arg
          null

    instance:
      augment:       0..n
      choice:        0..n
      config:        0..1
      container:     0..n
      description:   0..1
      if-feature:    0..n
      instance:      0..n
      instance-list: 0..n
      instance-type: 1
      leaf:          0..n
      leaf-list:     0..n
      list:          0..n
      mandatory:     0..1
      must:          0..n
      reference:     0..1
      status:        0..1
      when:          0..1
      construct: !coffee/function |
        (arg, params, children) -> 
          synth = @resolve 'feature', 'synthesizer'
          Model = children.ctype
          delete children.ctype
          ((synth Model) params).bind children

    instance-list:
      augment: 0..n
      choice: 0..n
      config: 0..1
      container: 0..n
      description: 0..1
      if-feature: 0..n
      instance: 0..n
      instance-list: 0..n
      instance-type: 1
      leaf: 0..n
      leaf-list: 0..n
      list: 0..n
      min-elements: 0..n
      max-elements: 0..n
      must: 0..n
      reference: 0..1
      status: 0..1
      when: 0..1
      construct: !coffee/function |
        (arg, params, children) -> 
          synth = @resolve 'feature', 'synthesizer'
          Model = children.ctype
          delete children.ctype
          unless (Model.get 'key')?
            throw @error "missing 'key' for #{Model.get 'name'} used in instance-list"
          item = ((synth Model) null).bind children
          #item = (class extends Model).bind children
          (synth.List params).set type: item, key: (item.get 'key')

    instance-type:
      construct: !coffee/function |
        (arg, params, children, ctx) ->
          ctx.ctype = (@resolve 'complex-type', arg)
          unless ctx.ctype?
            throw @error "unable to resolve '#{arg}' complex-type instance"
          null

# OVERRIDE various existing yang-v1-lang extensions
# ---
# The override: true informs that when THIS complex-types module is IMPORTED
# by another module, these following extensions should be merged into the 
# currently active extensions resolution table during preprocess/compile stages
yang-v1-lang:
  extension:
    module:
      complex-type:  0..n
      instance:      0..n
      instance-list: 0..n
      construct: !coffee/function |
        (arg, params, children, ctx, self) ->
          (self.origin.construct.apply this, arguments)
          .merge models: (@resolve 'complex-type')

    submodule:
      complex-type:  0..n
      instance:      0..n
      instance-list: 0..n

    container:
      instance:      0..n
      instance-list: 0..n

    grouping:
      instance:      0..n
      instance-list: 0..n

    input:
      instance:      0..n
      instance-list: 0..n

    output:
      instance:      0..n
      instance-list: 0..n

    type:
      instance-type: 0..1
      construct: !coffee/function |
        (arg, params, children, ctx, self) ->
          if children.ctype?
            ctx.type = children.ctype
            null
          else
            self.origin.construct.apply this, arguments

    leaf:
      construct: !coffee/function |
        (arg, params, children, ctx, self) ->
          synth = @resolve 'feature', 'synthesizer'
          if params.type['instance-identifier']?
            synth.BelongsTo params, -> @set model: children.type
          else
            self.origin.construct.apply this, arguments

    leaf-list:
      construct: !coffee/function |
        (arg, params, children, ctx, self) ->
          synth = @resolve 'feature', 'synthesizer'
          if params.type['instance-identifier']?
            synth.HasMany params, -> @set model: children.type
          else
            # the below is a bit fragile...
            self.origin.construct.apply this, arguments
