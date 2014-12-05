stormify = require '../../../src/stormify'
assert = require 'assert'
util = require 'util'
DS = stormify.DS

class StudentController extends DS.Controller

    beforeSave: ->
        super

        course = @model.get 'course'
        unless course instanceof DS.Model
            util.log 'given course details ' + util.inspect course
            # assert that proper data passed in for mapping to the user
            assert course? and course instanceof Object, "unable to create a new course without valid course details"
            course = @view.createRecord 'course', course
            course.save =>
                @model.set 'course', course
                #@model.save()
        else
            util.log 'given course refers to existing: ' + course.id


        address = @model.get 'address'
        unless address instanceof DS.Model
            util.log 'given address details ' + util.inspect address
            # assert that proper data passed in for mapping to the user
            assert address? and address instanceof Object, "unable to create a new address without valid address details"
            address = @view.createRecord 'address', address
            address.save =>
                @model.set 'address', address
                #@model.save()
        else
            util.log 'given address refers to existing: ' + address.id


        marks = @model.get 'marks'
        util.log "----- All marks: " + util.inspect marks
        @model.set 'marks', []
        for mark in marks
            newmarks = @model.get 'marks'
            unless mark instanceof DS.Model
                util.log "given mark " + util.inspect mark
                assert mark? and mark instanceof Object, "unable to create a new mark without valid mark details"           
                mark = @store.createRecord 'mark', mark
                mark.save =>
                    #saves the record in mark db
                    newmarks.push mark
                    @model.set 'marks', newmarks
                    @model.save()
            else
                util.log 'given mark refers to existing: ' + mark.id



module.exports = StudentController

