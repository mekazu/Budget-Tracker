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
	locals = {}
	totals = {}
	log("Loaded Index: " + indexCount++);
	list {group: 'bank'}, MONEY, (results) ->
		locals.bank = results
		list {group: 'expense'}, MONEY, (results) ->
			locals.expenses = results
			defineTotals locals
			res.render 'index.jade', {title: "Home", locals: look locals, "Locals:"}

app.post "/balance", (req, res) ->
	p = req.body
	look p, "The form sent to balance:"
	# Here we tie up origin as being the original key, otherwise it's just name
	origin = dislodge p, 'origin'
	look (p.key = name : if origin then origin else p.name), "Key definition:"
	action = dislodge p, 'action'
	validate req.body, MONEY, action, (err, row) ->
		if err
			res.send("Validation Error: " + err)
		else
			persist row, MONEY, action, (err, docs) ->
				log "Responding"
				res.send(if err then "Error: " + err else '')

app.listen(8743)

validate = (row, table, action, callback) ->
	if table == MONEY
		if row.group == 'expense'
			if action != 'delete'
				amount = parseFloat(row.amount)
				if isNaN(amount)
					callback "Amount is not numeric"
				row.amount = amount
	callback false, row

defineTotals = (locals) ->
	bank =
		name: 'Bank Balance',
		amount: sum locals.bank, 'balance'
	expense =
		name: 'Expenses Balance',
		amount: sum locals.expenses, 'amount', 'type', 'expense'
	total =
		name: 'Total Balance',
		amount: bank.amount + expense.amount
	locals.totals = [bank, expense, total]

sum = (list, p, negKey, negVal) ->
	balance = 0
	for obj in list
		amount = parseFloat(obj[p])
		if !isNaN(amount)
			if negKey and negVal and obj[negKey] == negVal
				balance -= amount
			else
				balance += amount
	balance

filter = (results, key, value) ->
	list = []
	for result in results
		list.push result if result[key] == value
	list

dislodge = (obj, property) ->
	value = obj[property]
	delete obj[property]
	log value, "Dislodged: "

list = (key, table, callback) ->
	look key, "Looking in " + table + " for: "
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
		else
			callback("Action: " + action + " not understood.");

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
