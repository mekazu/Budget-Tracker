express = require('express')
app = express.createServer()
MongoDb = require('mongodb').Db
MongoObjectID= require('mongodb').ObjectID
MongoServer= require('mongodb').Server
sys = require('sys')

database = (host, port, database) ->
	this.db= new MongoDb(database, new MongoServer(host, port, {auto_reconnect: true}, {}))
	this.db.open ->
		log "MongoDB Connected"

db = new database("localhost", 27017, "budget").db

MONEY = "money"

app.configure ->
	app.use express.static(__dirname + '/public')
	app.use(express.bodyParser())

indexCount = 0;
app.get '/', (req, res) ->
	debugger
	log("Loaded Index: " + indexCount++);
	list {}, MONEY, (results) ->
		res.render 'index.jade', {title: "Home", locals: {bank: results}}

app.post "/balance", (req, res) ->
	p = req.body
	look p, "Inspecting"
	p.key = name : if p.origin then p.origin else p.name
	look p.key, "Key definition:" 
	delete p.origin
	action = p.action
	delete p.action
	persist req.body, MONEY, action, (err, docs) ->
		res.send(if err then "Error: " + err else '')
app.listen(8743)

list = (key, table, callback) ->
	look key, "Looking in: " + table + " for: "
	db.collection table, (err, c) ->
		look err, "Error:" if err
		c.find key, (err, cursor) ->
			cursor.toArray (err, array) ->
				look array, "Results"
				callback(array)

persist = (row, table, action, callback) ->
	key = row.key
	delete row.key
	final = (err, docs) ->
		if err
			look err, "Error"
		look docs, "Success"
		db.close()
		callback(err, docs) if callback
	db.collection table, (err, c) ->
		if action == 'add'
			c.count key, (err, count) ->
				if count < 1
					c.insert [row], final
				else
					callback("Found " + count + " duplicate key on insert", null)
		else if action == 'change'
			c.findOne key, (err, doc) ->
				if look doc, "Before Update:"
					row._id = doc._id
					c.update key, row, {safe: true}, final
				else
					callback("Could not find the doc to update", null);
		else if action == 'replace'
			c.findOne key, (err, doc) ->
				if look doc, "Before Replace:"
					row._id = doc._id
					c.update key, row, {safe: true}, final
				else
					callback("Could not find the doc to update", null);
		else if action == 'delete'
			c.findOne key, (err, doc) ->
				if look doc, "Before delete"
					c.remove doc, {safe: true}, final
				else
					callback("Could not find the doc to delete", null);


log = (text, note) ->
	log note if note
	sys.puts text
	text

look = (obj, note) ->
	log note if note
	sys.puts sys.inspect obj
	obj

###
Object.prototype.whenisthiscalled = (head)->
	sys.puts("ok...")
	if head
		log head
	log this
	this

Object.prototype.alert = (head)->
	sys.inspect(this).log(head)
	this
###
