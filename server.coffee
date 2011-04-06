express = require('express')
app = express.createServer()
MongoDb = require('mongodb').Db
ObjectID= require('mongodb').BSONNative.ObjectID
MongoServer= require('mongodb').Server
sys = require('sys')
dateUtils = require('date-utils')

database = (host, port, database) ->
	this.db = new MongoDb(database, new MongoServer(host, port, {auto_reconnect: true}, {}))
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
	log "Loaded Index: " + indexCount++;
	list {group: 'bank'}, MONEY, (err, results) ->
		locals.bank = results
		list {group: 'expense'}, MONEY, (err, results) ->
			locals.expenses = results
			defineTotals locals
			res.render 'index.jade', {title: "Home", locals: look locals, "Locals:"}

app.post "/balance", (req, res) ->
	look p = req.body, "The form sent to balance:"
	id = dislodge p, 'id'
	look (p.key = _id : new ObjectID id), "Key definition:" if id
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
		if row.group == 'bank'
			row.unique = name : row.name
			if action != 'add'
				row.unique._id = $ne : row.key._id
			look row.unique, "Unique qualifier"
			if action != 'delete'
				callback "Amount is not numeric" if not makeFloat row, 'balance'
				callback "Epoch is not numeric"  if not makeFloat row, 'epoch'
		if row.group == 'expense'
			if action != 'delete'
				callback "Amount is not numeric" if not makeFloat row, 'amount'
				callback "Epoch is not numeric"  if not makeFloat row, 'epoch'
			row.unique = name : row.name, epoch : row.epoch
			if action != 'add'
				row.unique._id = $ne : row.key._id
	callback false, row

defineTotals = (locals) ->
	currentBank = max(locals.bank, 'epoch')
	sumExpenses = (epoch) ->
		sum locals.expenses, 'amount', 'type', 'expense', 'epoch', epoch
	look nextWeek = new Date(currentBank.epoch * 1000).addWeeks(1), "Next week:"
	nextWeekEpoch = nextWeek.getTime() / 1000
	expenseNextWeek = sumExpenses
	bank =
		name: 'Bank Balance'
		including: sum locals.bank, 'balance'
	expense =
		name: 'Expenses After Last Bank Update'
		including: sumExpenses currentBank.epoch
		excluding: sumExpenses currentBank.epoch - 1
		date: currentBank.date
	total =
		name: 'Total After today'
		including: bank.including + expense.including
		excluding: bank.including + expense.excluding
		date: currentBank.date
	oneWeek =
		name: 'Next Week'
		including: sumExpenses nextWeekEpoch
		excluding: sumExpenses nextWeekEpoch - 1
		date: formatDate nextWeekEpoch
	locals.totals = [bank, expense, total, oneWeek]

pad = (str, length) ->
	str = String(str);
	while (str.length < length)
		str = '0' + str
	str

formatDate = (epoch) ->
	d = new Date(epoch * 1000)
	pad(d.getDate(), 2) + '/' + d.getMonthAbbr() + '/' + d.getFullYear()

max = (list, p) ->
	amount = 0
	top = null
	for obj in list
		if didFloat obj, p
			if obj[p] > amount
				amount = obj[p]
				top = obj
		else
			log "Expected number: " + p + " is " + obj[p]
	top

sum = (list, p, negKey, negVal, epoch, after, before) ->
	balance = 0
	log "p: " + p + " negKey: " + negKey + " negVal: " + negVal + " epoch: " + epoch + " after: " + after + " before: " + before
	for obj in list
		amount = parseFloat(obj[p])
		if !isNaN(amount)
			amount = negafy obj, negKey, negVal, amount
			log "Amount: " + amount
			if didFloat obj, epoch
				if !isNaN after
					if obj[epoch] > after
						if !isNaN before
							if obj[epoch] < before
								balance += amount
							else
								log "After after but not before before"
						else
							balance += amount
					else
						log "Not after after"
				else if !isNaN before
					if obj[epoch] < before
						balance += amount
					else
						log "Not before before"
				else
					log "Not before before or after after"
			else
				balance += amount
	balance

didFloat = (obj, property) ->
	obj and property and obj[property] and makeFloat obj, property

makeFloat = (obj, property) ->
	ok = true
	if obj[property]
		ok = !isNaN obj[property]
		if ok
			obj[property] = parseFloat(obj[property])
	ok

negafy = (obj, negKey, negVal, amount) ->
	if negKey and negVal and obj[negKey] == negVal
		amount * -1
	else
		amount

dislodge = (obj, property) ->
	value = obj[property]
	delete obj[property]
	value

list = (key, table, callback) ->
	look key, "Looking in " + table + " for: "
	db.collection table, (err, c) ->
		callback(err, c) if err instanceof Error
		c.find key, (err, cursor) ->
			callback(err, cursor) if err instanceof Error
			cursor.toArray (err, array) ->
				callback(err, array)

ensureUnique = (connection, qualifier, callback) ->
	if qualifier
		connection.count qualifier, (err, count) ->
			callback(err, count)
	else
		callback(null, 0)

persist = (row, table, action, callback) ->
	key = dislodge row, 'key'
	unique = dislodge row, 'unique'
	final = (err, docs) ->
		if err
			look err, "Error"
		look docs, "Success"
		db.close()
		callback(err, docs) if callback
	db.collection table, (err, c) ->
		if action == 'add'
			ensureUnique c, unique, (err, count) ->
				if err instanceof Error
					callback err.message
				else if count < 1
					c.insert [row], final
				else
					callback "Found " + count + " duplicate key on insert"
		else if action == 'change'
			c.findOne key, (err, doc) ->
				if look doc, "Before Update:"
					ensureUnique c, unique, (err, count) ->
						if err instanceof Error
							callback err.message
						if count < 1
							c.update key, row, {safe: true}, final
						else
							callback "Found " + count + " duplicate key on insert"
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
