stormify = require '../../../src/stormify'
util = require 'util'
DS = stormify.DS

class MarkController extends DS.Controller

    beforeSave: ->
        super

module.exports = MarkController