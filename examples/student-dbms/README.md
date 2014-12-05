stormify-example
==============

Introduction:
-------------

This example, helps to understand  stormify with simple Student Management.

The following Datastore relations  are demonstrated in this execersise.
    'DS.belongsTo'
    'DS.hasMany'
    'DS.computed'

The DB is just designed to use most of stomify functionalities.


DB Schema Details :
-------------------

### Course table: 

Course table consists of the courses offered by the institute.

It consists of id, course name , department.  ID is the key.

### Address Table : 

Address table stores the student addresses. Address Table will be updated during the new student POST.
It consists of id, doorno ,street, place,city,zipcode,phoneno. ID is the key.


### Marks Table:

Marks table stores the student marks. Marks Table will be updated during the new student POST.
It consists of id, subject ,mark. ID is the key.


### Student Table:

Student table is the main table, manages the students.

It consists of id, name, courseid, address, marks.

courseid is a reference key for the Course Table. 
address is a  Address Table Schema (belongsTo relationship)
marks is a array of mark table (hasMany relationship).
result - checks the marks and generates the result (pass/fail)  (computed )


Operations :
----------

### 1. POST /courses

URL: http://localhost:8080/course

Input :
```
{
  "course" : 
	{
  	"name":"cloud computing",
  	"department":"CSE"
	}
}
```
Output :
```
{
  "course": {
    "id": "2be3332b-c71f-483f-9e8b-9106dcc29f43",
    "name": "cloud computing",
    "department": "CSE",
    "accessedOn": "2014-12-05T15:10:49.785Z",
    "modifiedOn": "2014-12-05T15:10:49.785Z",
    "createdOn": "2014-12-05T15:10:49.784Z"
  }
}
```
### 2. GET /courses
URL: http://localhost:8080/course

Output :
```
{
  "course": [
    {
      "id": "2be3332b-c71f-483f-9e8b-9106dcc29f43",
      "name": "cloud computing",
      "department": "CSE",
      "accessedOn": "2014-12-05T15:10:49.785Z",
      "modifiedOn": "2014-12-05T15:10:49.785Z",
      "createdOn": "2014-12-05T15:10:49.784Z"
    }
  ]
}
```
### 3. PUT  /courses/:id

URI: http://localhost:8080/course/2be3332b-c71f-483f-9e8b-9106dcc29f43

Input:
```
{
  "course": {
    "name": "NEW cloud computing",
    "department": "NCSE"
  }
}
```
Output:
```
{
  "course": [
    {
      "id": "2be3332b-c71f-483f-9e8b-9106dcc29f43",
      "name": "NEW cloud computing",
      "department": "NCSE",
      "accessedOn": "2014-12-05T15:10:49.785Z",
      "modifiedOn": "2014-12-05T15:12:36.560Z",
      "createdOn": "2014-12-05T15:10:49.784Z"
    }
  ]
}
```

### 4. DELETE /course/:id
http://localhost:8080/course/2be3332b-c71f-483f-9e8b-9106dcc29f43
```
204 No Content
```


### 5. POST /students

In this input data,  all data are passed with details.
Course will be saved in Course table, Address will be saved in the Address table, Marks will be saved to Marks table.

URI: http://localhost:8080/students

Input:
```
{
  "student": {
    "name": "suresh",
    "course": {
      "name": "cloud computing",
      "department": "CSE"
    },
    "address": {
      "doorno": "32A",
      "street": "B.G Road",
      "place": "bilekelli",
      "city": "bangalore",
      "zipcode": 560033,
      "phoneno": 9884049883
    },
    "marks": [
      {
        "subject": "tamil",
        "mark": 40
      },
      {
        "subject": "english",
        "mark": 10
      }
    ]
  }
}
```
Output:
```
{
  "student": {
    "id": "817e45d7-15b1-42f5-8e55-aacaaa7c1eec",
    "name": "suresh",
    "address": "7af3150e-e521-4575-8e5b-307a39bfca5a",
    "course": "38601f99-be55-4c9e-83f1-c6c45d1806b9",
    "marks": [
      "9de50d5f-6cc9-4ebd-b7d9-36ad51fae832",
      "e8ebbfc9-3460-46ed-a258-665207445afe"
    ],
    "result": "pass",
    "accessedOn": "2014-12-05T15:14:42.769Z",
    "modifiedOn": "2014-12-05T15:14:42.769Z",
    "createdOn": "2014-12-05T15:14:42.769Z"
  }
}
```
Note:  Marks table will be updated with the marks data and address table will be updated with the address data.

### 6. POST /students

In this input data,  "courseid" is a reference course table reference key. 
Address will be saved in the Address table, Marks will be saved to Marks table.

URI: http://localhost:8080/students

Input:
```
{
  "student": {
    "name": "suresh kumar",
    "course": "38601f99-be55-4c9e-83f1-c6c45d1806b9",
    "address": {
      "doorno": "32A1111111",
      "street": "B.G Road 1111111",
      "place": "bilekelli 111111111",
      "city": "bangalore 11111111",
      "zipcode": 111222,
      "phoneno": 8888899999
    },
    "marks": [
      {
        "subject": "tamil",
        "mark": 98
      },
      {
        "subject": "english",
        "mark": 95
      }
    ]
  }
}
```
Output:
```
{
  "student": {
    "id": "f3f5b0c6-25ee-4c04-9fcb-62c194bdddfa",
    "name": "suresh kumar",
    "address": "a6c98c11-3f89-49d2-a732-0527f4a511b0",
    "course": "38601f99-be55-4c9e-83f1-c6c45d1806b9",
    "marks": [
      "82ee9f84-ae0b-4536-b390-f5481d904c75",
      "babd49ea-2f7b-49ed-a9a5-7d740aeaf94a"
    ],
    "result": "pass",
    "accessedOn": "2014-12-05T15:22:44.845Z",
    "modifiedOn": "2014-12-05T15:22:44.845Z",
    "createdOn": "2014-12-05T15:22:44.845Z"
  }
}
```
Note:  Marks table will be updated with the marks data and address table will be updated with the address data.


### 7. GET /course/
URI: http://localhost:8080/course/

Output :
```
{
  "course": [
    {
      "id": "38601f99-be55-4c9e-83f1-c6c45d1806b9",
      "name": "cloud computing",
      "department": "CSE",
      "accessedOn": "2014-12-05T15:14:42.772Z",
      "modifiedOn": "2014-12-05T15:14:42.772Z",
      "createdOn": "2014-12-05T15:14:42.772Z"
    }
  ]
}
```
Note: Only one reference to Course table exist. In the 2nd POST on /students we used the existing course-id.

### 8. DELETE /students/:id
URI: http://localhost:8080/students/f3f5b0c6-25ee-4c04-9fcb-62c194bdddfa

deletes the given student from the student table. But does not remove address, marks from the mark table (as of now).






