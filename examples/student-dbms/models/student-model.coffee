stormify = require '../../../src/stormify'

DS = stormify.DS

class StudentModel extends DS.Model

    name: 'student'
    schema:
        name:       DS.attr 'string', required: true
        address:	  DS.belongsTo 'address', required: true
        course:	    DS.belongsTo 'course', required: true  # key for major table
        marks:		  DS.hasMany 'mark', required: true

module.exports = StudentModel
