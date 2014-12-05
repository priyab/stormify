stormify = require '../../../src/stormify'

class StudentDataStore extends stormify.DS

    name: "student-ds"
    constructor: (opts) ->

        super opts
        store = this
        @contains 'address',
            model: require '../models/address-model'
            controller: require '../controllers/address-controller'

        @contains 'course',
            model: require '../models/course-model'
            controller: require '../controllers/course-controller'

        @contains 'students',
            model: require '../models/student-model'
            controller: require '../controllers/student-controller'

        @contains 'mark',
            model: require '../models/mark-model'
            controller: require '../controllers/mark-controller'

        @initialize()

module.exports = StudentDataStore