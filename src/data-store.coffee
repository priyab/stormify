# mixin = require './mixin'
# DynamicResolver    = require './dynamic-resolver'
# extends mixin DynamicResolver
#
assert = require 'assert'
bunyan = require 'bunyan'

#---------------------------------------------------------------------------------------------------------

SR = require './stormregistry'

#-----------------------------------
# DataStoreRegistry
#
# Uses deferred DataStoreModel instantiation to take place only on @get
#
class DataStoreRegistry extends SR

    constructor: (@collection,opts) ->
        @store = opts?.store
        assert @store? and @store.contains(@collection), "cannot construct DataStoreRegistry without valid store containing '#{collection}' passed in"

        @log = opts?.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

        @entity = @store.contains(@collection)

        @on 'load', (key,val) ->
            @log.debug entity:@entity.name,key:key,'loading a persisted record'
            entry = val?[@entity.name]
            if entry?
                entry.id = key
                entry.saved = true
                @add key, entry
        @on 'ready', ->
            size = Object.keys(@entries)?.length
            @log.info entity:@entity.name,size:size,"registry for '#{@collection}' initialized with #{size} records"

        datadir = opts?.datadir ? '/tmp'
        super
            log: @log
            path: "#{datadir}/#{@collection}.db" if opts?.persist

    keys: -> Object.keys(@entries)

    get: (id) ->
        entry = super id
        return null unless entry?
        unless entry instanceof DataStoreModel
            @log.info id:id, "restoring #{@entity.name} from registry using underlying entry"

            # we try here since we don't know if we can successfully createRecord during restoration!
            try
                record = @store.createRecord @entity.name, entry
                record.isSaved = true
                @update id, record, true
            catch err
                @log.warn method:'get',id:id,error:err, "issue while trying to restore a record of '#{@entity.name}' from registry"
                return null

        super id

#---------------------------------------------------------------------------------------------------------

class DataStoreModel extends SR.Data

    @attr      = (type, opts)  -> type: type, opts: opts
    @belongsTo = (model, opts) -> mode: 1, model: model, opts: opts
    @hasMany   = (model, opts) -> mode: 2, model: model, opts: opts
    @computed  = (func, opts)  -> computed: func, opts: opts
    @computedHistory = (model, opts) -> mode: 3, model: model, opts: opts

    @schema =
        createdOn:  @attr 'date'
        modifiedOn: @attr 'date'
        accessedOn: @attr 'date'
        error:      @attr 'object'

    async = require 'async'
    extend = require('util')._extend
    uuid  = require 'node-uuid'

    schema: {}  # defined by sub-class
    store: null # auto-set by DataStore during createRecord

    constructor: (data,opts) ->
        @isSaved = false
        @isDestroyed = false

        @store = opts?.store
        @log = opts?.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name
        @log.debug data:data, "constructing #{@name}"

        @useCache = opts?.useCache

        # initialize all relations and properties according to schema
        @relations = {}
        @properties = {}

        @schema = extend @schema, DataStoreModel.schema

        for key,val of @schema
            @properties[key] = extend {},val
            @relations[key] = {
                type: switch val.mode
                    when 1 then 'belongsTo'
                    when 2 then 'hasMany'
                model: val.model
            } if val.model?

        @id = data?.id
        @id ?= uuid.v4()
        @version ?= 1

        @setProperties data

        # verify basic schema compliance during construction
        violations = []
        for name,prop of @properties
            #console.log name
            prop.value ?= switch
                when typeof prop.opts?.defaultValue is 'function' then prop.opts.defaultValue()
                else prop.opts?.defaultValue
            unless prop.value
                violations.push "'#{name}' is required for #{@constructor.name}" if prop.opts?.required
            else
                check = switch prop.type
                    when 'string' or 'number' or 'boolean'
                        typeof prop.value is prop.type
                    when 'date'
                        if typeof prop.value is 'string'
                            prop.value = new Date(prop.value)
                        prop.value instanceof Date
                    when 'array'
                        prop.value instanceof Array
                    else
                        true

                violations.push "'#{name}' must be a #{prop.type}" if prop.type? and not check

                if prop.model? and prop.value instanceof Array and prop.mode isnt 2
                    violations.push "'#{name}' cannot be an array of #{prop.model}"
            prop.value ?= [] if prop.mode is 2

        @log.debug "done constructing #{@name}"
        assert violations.length == 0, violations

    # customize how data gets saved into DataStoreRegistry
    # this operation cannot be async, it means it will extract only known current values.
    # but it doesn't matter since computed data will be re-computed once instantiated
    serialize: (opts) ->
        assert @isDestroyed is false, "attempting to serialize a destroyed record"

        result = id: @id
        for prop,data of @properties when data.value?
            x = data.value
            result[prop] = switch
                when x instanceof DataStoreModel
                    if opts?.embedded is true
                        x.serialize()
                    else
                        x.id
                when x instanceof Array
                    (if y instanceof DataStoreModel then y.id else y) for y in x
                else x

        return result unless opts?.tag is true

        data = {}
        data["#{@name}"] = result
        data

    get: (property, opts..., callback) ->
        assert @properties.hasOwnProperty(property), "attempting to retrieve '#{property}' which doesn't exist in this model"
        #assert @isDestroyed is false, "attempting to retrieve '#{property}' from a destroyed record"

        prop = @properties[property]

        enforceCheck = if opts.length then opts[0].enforce else true

        # simple property options enforcement routine
        #
        # unique: true (for array types, ensures only unique entries)
        enforce = (x) ->
            return x unless enforceCheck

            @log.debug "checking #{property} with #{x}"

            x ?= switch
                when typeof prop.opts?.defaultValue is 'function' then prop.opts.defaultValue()
                else prop.opts?.defaultValue

            violations = []
            validator = prop?.opts?.validator
            val = switch
                when not x?
                    violations.push "'#{property}' is a required property for #{@name}" if prop.opts?.required
                    x
                when prop.model? and typeof prop.model isnt 'string'
                    unless x instanceof prop.model
                        violations.push "'#{property}' must be an instance of #{prop.model.prototype?.constructor?.name}"
                    switch prop.mode
                        when 1 then x
                        when 2 then [ x ]
                when prop.model? and x instanceof Array and prop.mode is 2
                    results = (@store.findRecord(prop.model,id) for id in prop.value unless id instanceof DataStoreModel).filter (e) -> e?
                    if results.length then results else x
                when prop.model? and x instanceof DataStoreModel
                    switch prop.mode
                        when 1 then x
                        when 2 then [ x ]
                when prop.model? and x instanceof Object then x
                when prop.model? and prop.mode isnt 3
                    #console.log "#{prop.model} using #{x}"
                    record = @store.findRecord(prop.model,x)
                    unless record?
                        violations.push "'#{property}' must be a model of #{prop.model}, unable to find using #{x}"
                    switch prop.mode
                        when 1 then record
                        when 2 then [ record ]
                        when 3 then null # null for now
                when x instanceof Array and prop.opts.unique then x.unique()
                else x
            assert violations.length is 0, violations
            if validator? then validator.call(@, val) else val

        # should provide resolved results
        if typeof prop?.computed is 'function' and @store.isReady
            @log.debug "issuing get on computed property: %s", property
            value = prop.value = enforce.call @, prop.value
            if value and @useCache and prop.cachedOn and (prop.opts?.cache isnt false)
                cachedFor = (new Date() - prop.cachedOn)/1000
                if cachedFor < @useCache
                    @log.debug method:'get',property:property,id:@id,"returning cached value: #{value} will refresh in #{@useCache - cachedFor} seconds"
                    callback? null, value
                    return value
                else
                    @log.info method:'get',property:property,id:@id, "re-computing expired cached property (#{cachedFor} secs > #{@useCache} secs)"

            @log.debug method:'get',property:property,id:@id,"computing a new value!"
            cacheComputed = (err, value) =>
                unless err and @useCache
                    prop.value = value
                    prop.cachedOn = new Date()
                callback? err, enforce.call(@,value)

            try
                if prop.opts?.async
                    prop.computed.apply @, [cacheComputed,prop]
                else
                    value = prop.value = prop.computed.apply @
                    callback? null, enforce.call @, prop.value
            catch err
                @log.warn method:'get',property:property,id:@id,error:err, "issue during executing computed property"
                callback? null, err

            value # this is to avoid returning a function when direct 'get' is invoked
        else
            @log.debug "issuing get on static property: %s", property
            prop.value = enforce.call(@, prop?.value) if @store.isReady
            value = prop.value
            @log.debug method:'get',property:property,id:@id,"issuing get on #{property} with #{value}"
            callback? null, value
            value

    getProperties: (props, callback) ->
        if typeof props is 'function'
            callback = props
            props = @properties
        else
            props = [ props ] if props? and props not instanceof Array
            props ?= @properties

        self = @
        tasks = {}
        for property, value of props
            if typeof value.computed is 'function'
                do (property) ->
                    self.log.debug "scheduling task for computed property: #{property}..."
                    tasks[property] = (callback) -> self.get property, callback
                    self.log.debug "completed task for computed property: #{property}..."

        start = new Date()
        async.parallel tasks, (err, results) =>
            results.id = @id
            @log.trace method:'getProperties',id:@id,results:results, 'computed properties'
            statics = {}
            statics[property] = @get property for property, data of props when not data.computed
            @log.trace method:'getProperties',id:@id,statics:statics, 'static properties'
            results = extend statics, results
            delete results[property] for property of results when property.indexOf('++') > 0

            duration = new Date() - start
            (@log.warn
                method:'getProperties'
                duration:duration
                numComputed: Object.keys(tasks).length
                id: @id
                computed: Object.keys(tasks)
                "processing properties took #{duration} ms exceeding threshold!") if duration > 1000

            @log.debug method:'getProperties',id:@id,results:Object.keys(results), 'final results before callback'
            callback results

    set: (property, opts..., value) ->
        assert @isDestroyed is false, "attempting to set a value to a destroyed record"

        return if @schema? and not @properties.hasOwnProperty(property)

        if typeof value is 'function'
            if property instanceof Array
                @properties[prop] = inherit: true for prop in property
                property = property.join '++'
            @properties[property]?.computed = value
            @properties[property] ?= computed: value
        else
            ArrayEquals = (a,b) -> a.length is b.length and a.every (elem, i) -> elem is b[i]
            cval = @properties[property]?.value
            nval = value
            isDirty = switch
                when not @properties.hasOwnProperty(property) then false # when being set for the first time
                when cval is nval then false
                when cval instanceof Array and nval instanceof Array then not ArrayEquals cval,nval
                else true
            @log.debug method:'set',property:property,id:@id,"compared #{property} #{cval} with #{nval}... isDirty:#{isDirty}"
            setting = isDirty:isDirty,lvalue:cval,value:nval
            if @properties.hasOwnProperty(property)
                if @properties[property].opts?.required
                    assert value?, "must set value for required property '#{property}'"

                @properties[property] = extend @properties[property], setting
            else
                @properties[property] = setting
        # now apply opts into the property if applicable
        #@properties[property].opts = opts if opts?

    setProperties: (obj) -> @set property, value for property, value of obj

    update: (data) ->
        assert @isDestroyed is false, "attempting to update a destroyed record"

        # if controller associated, issue the updateRecord action call
        @controller?.beforeUpdate? data
        @setProperties data
        @controller?.afterUpdate? data

    # deal with DIRT properties
    dirtyProperties: -> (prop for prop, data of @properties when data.isDirty)
    clearDirty: -> data.isDirty = false for prop, data of @dirtyProperties()
    isDirty: (properties) ->
        dirty = @dirtyProperties()
        return (dirty.length > 0) unless properties?
        properties = [ properties ] unless properties instanceof Array
        dirty = dirty.join ' '
        properties.some (prop) -> ~dirty.indexOf prop

    removeReferences: (model,isSaveAfter) ->
        return unless model instanceof DataStoreModel
        for key, relation of @relations
            continue unless relation.model is model.name
            @log.debug method:'removeReferences',id:@id,"clearing #{key}.#{relation.type} '#{relation.model}' containing #{model.id}..."
            try
                switch relation.type
                    when 'belongsTo' then @set key, null if @get(key)?.id is model.id
                    when 'hasMany'   then @set key, @get(key).without id:model.id
            catch err
                @log.warn method:'removeReferences', error:err, "issue encountered while attempting to clear #{@name}.#{key} where #{relation.model}=#{model.id}"

        @save() if isSaveAfter is true

    # specifying 'callback' has special significance
    #
    # when 'callback' is passed in, it indicates that the caller is the original CREATOR
    # of this record and would handle the case where this record is NOT yet saved
    #
    # this means that when it is called without callback and the record is NOT yet saved
    # no operation will take place!
    #
    save: (callback) ->
        assert @isDestroyed is false, "attempting to save a destroyed record"

        switch
            # when called with callback ALWAYS perform commit action
            when callback?
                try
                    @controller?.beforeSave?()
                catch err
                    @log.error method:'save',record:@name,id:@id,error:err,'failed to satisfy beforeSave controller calls'
                    callback err, null
                    throw err

                @getProperties (props) =>
                    unless props?
                        @log.error method:'save',id:@id,'failed to retrieve properties following save!'
                        return callback 'save failed to retrieve updated properties!', null

                    @log.info method:'save',record:@name,id:@id, "saving a 'new' record"
                    try
                        @store?.commit @
                        @clearDirty()
                        @isSaved = true
                        @controller?.afterSave?()
                        callback null, @, props
                    catch err
                        @log.error method:'save',record:@name,id:@id,error:err,'failed to commit record to the store!'
                        callback err, null
                        throw err

            # when this record hasn't been saved yet, DO NOT commit to the store!
            when not @isSaved then return

            # otherwise, we try to commit
            else
                @store?.commit @
                @clearDirty()

    destroy: (callback) ->
        # if controller associated, issue the destroy action call
        @controller?.beforeDestroy?()
        @isDestroy = true
        @store?.commit @
        @controller?.afterDestroy?()
        @isDestroyed = true
        callback? null, true

#---------------------------------------------------------------------------------------------------------

EventEmitter = require('events').EventEmitter

class DataStoreController extends EventEmitter

    constructor: (opts) ->
        assert opts? and opts.model instanceof DataStoreModel, "unable to create an instance of DS.Controller without underlying model!"

        # XXX - may change to check for instanceof DataStoreView in the future
        #assert opts? and opts.view  instanceof DataStoreView, "unable to create an instance of DS.Controller without a proper view!"

        @model = opts.model
        @store = @view  = opts.view # hack for now to preserve existing controller behavior

        @log = opts.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

    beforeUpdate: (data) ->
        @emit 'beforeUpdate', [ @model.name, @model.id ]

    afterUpdate: (data) ->
        @model.set 'modifiedOn', new Date()
        @emit 'afterUpdate', [ @model.name, @model.id ]

    beforeSave: ->
        @emit 'beforeSave', [ @model.name, @model.id ]

        @log.trace method:'beforeSave', 'we should auto resolve belongsTo and hasMany here...'

        createdOn = @model.get 'createdOn'
        unless createdOn?
            @model.set 'createdOn', new Date()
            @model.set 'modifiedOn', new Date()
            @model.set 'accessedOn', new Date()

        # when prop.model? and x instanceof Object
        #     try
        #         inverse = prop.opts?.inverse
        #         x[inverse] = @ if inverse?
        #         record = @store.createRecord prop.model,x
        #         record.save()
        #     catch err
        #         @log.warn error:err, "attempt to auto-create #{prop.model} failed"
        #         record = x
        #     #XXX - why does record.save() hang?
        #     record

    afterSave: ->
        @emit 'afterSave', [ @model.name, @model.id ]

    beforeDestroy: ->
        @emit 'beforeDestroy', [ @model.name, @model.id ]

        @log.info method:'beforeDestroy', model:@model.name, id:@model.id, 'invoking beforeDestroy to remove external references to this model'
        # go through all model relations and remove reference back to the @model
        for key,relation of @model.relations
            @log.debug method:'beforeDestroy',key:key,relation:relation,"checking #{key}.#{relation.type} '#{relation.model}'"
            try
                switch relation.type
                    when 'belongsTo' then @model.get(key)?.removeReferences? @model, true
                    when 'hasMany'   then target?.removeReferences? @model, true for target in @model.get(key)
            catch err
                @log.warn method:'beforeDestroy',key:key,relation:relation,"ignoring relation to '#{key}' that cannot be resolved"

    afterDestroy: ->

        @emit 'afterDestroy', [ @model.name, @model.id ]

#---------------------------------------------------------------------------------------------------------

# Wrapper around underlying DataStore
#
# Used during store.open(requestor) in order to provide access context
# for store operations. Also, DataStore sub-classes can override the
# store.open call to manipulate the views into the underlying entities
class DataStoreView

    extend = require('util')._extend

    constructor: (@store, @requestor) ->
        assert store instanceof DataStore, "cannot provide View without valid DataStore"
        @entities = extend {}, @store.entities
        @log = @store.log?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

    createRecord: (args...) -> @store.createRecord.apply @, args
    deleteRecord: (args...) -> @store.deleteRecord.apply @, args
    updateRecord: (args...) -> @store.updateRecord.apply @, args
    findRecord:   (args...) -> @store.findRecord.apply @, args
    findBy:       (args...) -> @store.findBy.apply @, args
    find:         (args...) -> @store.find.apply @, args

#---------------------------------------------------------------------------------------------------------

class DataStore extends EventEmitter

    # various extensions available from this class object
    @Model      = DataStoreModel
    @Controller = DataStoreController
    @View       = DataStoreView
    @Registry   = DataStoreRegistry

    @attr       = @Model.attr
    @belongsTo  = @Model.belongsTo
    @hasMany    = @Model.hasMany
    @computed   = @Model.computed
    @computedHistory = @Model.computedHistory

    async = require 'async'
    uuid  = require 'node-uuid'
    extend = require('util')._extend

    name: null # must be set by sub-class

    adapters: {}
    adapter: (type, module) -> @adapters[type] = module if type? and module?
    using: (adapter) -> @adapters[adapter]

    # stores: {}
    # link: (store) -> @stores[store.name] = store if store?

    constructor: (opts) ->
        @name ?= opts?.name

        assert @name?, "cannot construct DataStore without naming this store!"

        @log = opts?.auditor?.child class: @constructor.name
        @log ?= new bunyan name: @constructor.name

        @collections = {} # the name of collection mapping to entity
        @entities = {}    # the name of entity mapping to entity object
        @entities = extend(@entities, opts.entities) if opts?.entities?

        @authorizer = opts?.authorizer

        @isReady = false

        # if @constructor.name != 'DataStore'
        #   assert Object.keys(@entities).length > 0, "cannot have a data store without declared entities!"

    initialize: ->
        return if @isReady

        console.log "initializing a new DataStore: #{@name}"
        @log.info method:'initialize', 'initializing a new DataStore: %s', @name
        for collection, entity of @collections
            do (collection,entity) =>
                entity.registry ?= new DataStoreRegistry collection, log:@log,store:@,persist:entity.persist
                if entity.static?
                    entity.registry.once 'ready', =>
                        @log.info collection:collection, 'loading static records for %s', collection
                        for entry in entity.static
                            entry.saved = true
                            entity.registry.add entry.id, entry
                        @log.info collection:collection, "autoloaded #{entity.static.length} static records"

        # setup any authorizer reference to this store
        if @authorizer instanceof DataStore
            @references @authorizer.contains 'identities'
            @authorizer.references @contains 'sessions'

        @log.info method:'initialize', 'initialization complete for: %s', @name
        console.log "initialization complete for: #{@name}"
        @isReady = true
        # this is not guaranteed to fire when all the registries have been initialized
        process.nextTick => @emit 'ready'

    # used to denote 'collection' that is stored inside this data store
    contains: (collection, entity) ->
        return @collections[collection] unless entity?

        entity.name = entity.model.prototype.name
        entity.container = @
        entity.persist ?= true # default is to persist data
        entity.cache   ?= 1 # default cache for 1 second
        entity.controller ?= DataStoreController
        entity.collection = collection

        @collections[collection] = @entities[entity.name] = entity
        @log.info collection:collection, "registered a collection of '#{collection}' into the store"

    # used to denote entity that is stored outside this data store
    references: (entity) ->
        assert entity.name? and entity.container instanceof DataStore, "cannot reference an entity that isn't contained by another store!"

        entity = extend {}, entity # get a copy of it
        entity.external = true # denote that this entity is an external reference!
        entity.persist = false
        entity.cache   = false
        @entities[entity.name] = entity
        @log.info reference:entity.name, "registered a reference to '#{entity.name}' into the store"

    #-------------------------------
    # main usage functions

    # opens the store according to the provided requestor access constraints
    # this should be subclassed for view control based on requestor
    open: (requestor) -> new DataStoreView @, requestor

    # register callback for being called on specific event against a collection
    #
    when: (collection, event, callback) ->
        entity = @contains collection
        assert entity? and entity.registry? and event in ['added','updated','removed'] and callback?, "must specify valid collection with event and callback to be notified"
        entity.registry.once 'ready', -> @on event, (entry) -> process.nextTick -> callback entry

    createRecord: (type, data) ->
        @log.debug method:"createRecord", type: type, data: data
        try
            entity = @entities[type]
            record = new entity.model data,store:entity.container,log:@log,useCache:entity.cache

            # XXX - should consider this ONLY when created from a view
            record.controller = new entity.controller
                model:record
                view: this
                log: @log

            @log.info  method:"createRecord", id: record.id, 'created a new record for %s', record.constructor.name
            #@log.debug method:"createRecord", record:record
        catch err
            @log.error error:err, "unable to instantiate a new DS.Model for #{type}"
            throw err
        record

    deleteRecord: (type, id, callback) ->
        match = @findRecord type, id
        callback null unless match?
        match.destroy callback

    updateRecord: (type, id, data, callback) ->
        record = @findRecord type, id
        callback null unless record?
        record.update data
        record.save callback

    findRecord: (type, id) ->
        return unless type? and id?
        assert @entities[type]?.registry instanceof DataStoreRegistry, "trying to findRecord for #{type} without registry!"
        @entities[type]?.registry?.get id

    # findBy returns the matching records directly (similar to findRecord)
    findBy: (type, condition, callback) ->
        return callback "invalid findBy query params!" unless type? and typeof condition is 'object'

        @log.debug method:'findBy',type:type,condition:condition, 'issuing findBy on requested entity'

        records = @entities[type]?.registry?.list() or []

        query = condition
        hit = Object.keys(query).length
        results = records.filter (record) =>
            match = 0
            for key,val of query
                try
                    x = record.get(key)
                catch err
                    @log.warn method:'findBy',type:type,id:record.id,error:err,'skipping bad record...'
                    return false
                match += 1 if x is val or (x instanceof DataStoreModel and x.id is val)
            if match is hit then true else false

        unless results?.length > 0
            @log.debug method:'findBy',type:type,condition:query,'unable to find any records for the condition!'
        else
            @log.debug method:'findBy',type:type,condition:query,'found %d matching results',results.length
        callback? null, results
        results

    find: (type, query, callback) ->
        _entity = @entities[type]
        return callback "DS: unable to find using unsupported type: #{type}" unless _entity?

        ids = switch
            when query instanceof Array then query
            when query instanceof Object
                results = @findBy type, query
                results.map (record) -> record.id
            when query? then [ query ]
            else _entity.registry?.keys()

        self = @
        tasks = {}
        for id in ids
            do (id) ->
                tasks[id] = (callback) ->
                    match = self.findRecord type, id
                    return callback null unless match? and match instanceof DataStoreModel
                    # trigger a fresh computation and validations on the match
                    try
                        match.getProperties (properties) -> callback null, match
                    catch err
                        self.log.warn error:err,type:type,id:id, 'unable to obtain validated properties from the matching record'
                        # below silently ignores this record
                        callback null

        @log.debug method:'find',type:type,query:query, 'issuing find on requested entity'
        async.parallel tasks, (err, results) =>
            if err?
                @log.error err, "error was encountered while performing find operation on #{type} with #{query}!"
                return callback err

            matches = (entry for key, entry of results when entry?)
            unless matches?.length > 0
                @log.debug method:'find',type:type,query:query,'unable to find any records matching the query!'
            else
                @log.debug method:'find',type:type,query:query,'found %d matching results',matches.length

            callback null, matches

    commit: (record) ->
        return unless record instanceof DataStoreModel

        @log.debug method:"commit", record: record

        registry = @entities[record.name]?.registry
        assert registry?, "cannot commit '#{record.name}' into store which doesn't contain the collection"

        action = switch
            when record.isDestroy
                registry.remove record.id
                'removed'
            when not record.isSaved
                exists = record.id? and registry.get(record.id)?
                assert not exists, "cannot commit a new record '#{record.name}' into the store using pre-existing ID: #{record.id}"

                # if there is no ID specified for this entity, we auto-assign one at the time we commit
                record.id ?= uuid.v4()
                registry.add record.id, record
                'added'
            when record.isDirty()
                record.changed = true
                registry.update record.id, record
                delete record.changed
                'updated'

        # may be high traffic events, should listen only sparingly
        @emit 'commit', [ action, record.name, record.id ]
        @log.info method:"commit", id:record.id, "#{action} '%s' on the store registry", record.constructor.name

    #------------------------------------
    # useful for some debugging cases...
    dump: ->
        for name,entity of @entities
            records = entity.registry?.list()
            for record in records
                @log.info model:name,record:record.serialize(),method:'dump', "DUMP"

#---------------------------------------------------------------------------------------------------------

module.exports = DataStore
