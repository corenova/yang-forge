      

        # if (output?.value?.get? 'yang') is 'module'
        #   output.value.merge (this.match /.*\/.*/) # merge exported metadata
        # output?.value

The below `sub` statement is **not** a part of Yang 1.0 specification,
but provided as part of the `yang-core-compiler` so that it can be
used to provide constraint enforcement around sub-statements validity
and cardinality when a new statement extended via the schema
`extension` facility.

      @set 'yang/sub',
        argument: 'extension-name'
        resolver: (arg, params) -> params?.value
        value: '0..1'

The below `supplement` statement is also **not** a part of Yang 1.0
specification, but provided as part of the `yang-core-compiler` so
that it can be used to provide schema driven augmentations to
pre-defined extension statements.

      @set 'yang/supplement',
        argument: 'extension-name'
        resolver: (arg, params) -> @merge "yang/#{arg}", params; null
        sub: '0..n'

      compileStatement: (statement) ->
        return unless statement? and statement instanceof Object

        if !!statement.prf
          target = (@get "module/#{statement.prf}")?.get? "yang/#{statement.kw}"
        else
          target = @get "yang/#{statement.kw}"

        normalize = (statement) -> ([ statement.prf, statement.kw ].filter (e) -> e? and !!e).join ':'
        # keyword = normalize statement
        # target = @get keyword

        unless target?
          console.log "WARN: unrecognized keyword extension '#{normalize statement}', skipping..."
          return null

        # Special treatment of 'module' by temporarily declaring itself into the metadata
        if statement.kw is 'module'
          @set "module/#{statement.arg}", this
          
        # TODO - add enforcement for cardinality specification '0..1', '0..n', '1..n' or '1'
        results = (@compileStatement stmt for stmt in statement.substmts when switch
          # when not (meta = @get keyword)?
          #   console.log "WARN: unable to find metadata for #{keyword}"
          #   false
          when not (target.hasOwnProperty stmt.kw)
            console.log "WARN: #{statement.kw} does not have sub-statement declared for #{stmt.kw}"
            false
          else true
        )
        params = (results.filter (e) -> e? and e.value?).reduce ((a,b) -> a[b.name] = b.value; a), {}
        value = switch
          when target.resolver instanceof Function
            target.resolver.call this, statement.arg, params, target
          when (Object.keys params).length > 0
            class extends (@get 'default-resolver')
          else
            statement.arg

        value?.set? yang: statement.kw
        value?.extend? params

        (@set "#{statement.kw}/#{statement.arg}", value) if (target.export is true) or (target.meta is true)

        if target.meta is true
          return null

        return switch
          when statement.substmts?.length > 0
            name: (statement.arg ? statement.kw), value: value
          else
            name: statement.kw, value: value
