stormify = require '../../../src/stormify'
util = require 'util'
DS = stormify.DS

class AddressController extends DS.Controller

    beforeSave: ->
        super

module.exports = AddressController