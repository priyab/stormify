stormify = require '../../../src/stormify'
util = require 'util'
DS = stormify.DS

class CourseController extends DS.Controller

    beforeSave: ->
        super

module.exports = CourseController