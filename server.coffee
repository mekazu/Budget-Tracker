express			= require('express')
sys					= require('sys')
dateUtils		= require('date-utils')
util				= require('./server/util.js')
mongodb			= require('mongodb')

MongoDb			= mongodb.Db
ObjectID		= mongodb.BSONNative.ObjectID
MongoServer = mongodb.Server

MONEY = "money"
USER = "user"

app = express.createServer()
Database = (host, port, database) ->
	this.db = new MongoDb(database, new MongoServer(host, port, {auto_reconnect: true}, {}))
	this.db.open ->
		log "MongoDB Connected"

db = new Database("localhost", 27017, "budget").db
app.configure ->
	app.use express.static(__dirname + '/public')
	app.use express.bodyParser()
	app.use express.cookieParser()
	app.use express.session(secret: "Ci93kLKjvlk3l2jcXK3k")

indexCount = 0;
app.get '/', (req, res) ->
	# Prefs are stored in session and relayed to locals
	prefs = preferences req
	ses = req.session
	initSession(ses, prefs)
	locals = {prefs: prefs, log: log, signon: [ses.account]}
	render = ->
		res.render 'index.jade', {title: "Budget Diary", locals: locals}
	if ses.account.anon and not ses.account._id
		# Unregistered user who hasn't done anything yet
		prefs.anon = ses.account.anon
		render()
	else
		# User with something to display (not ses.account.anon or ses.account._id)
		if ses.account.user
			# Registered User
			prefs.user = ses.account.user
		list {group: 'bank', account: ses.account._id}, MONEY, (err, results) ->
			locals.bank = results
			list {group: 'expense', account: ses.account._id}, MONEY, (err, results) ->
				locals.expense = results
				defineTotals locals
				log "Defined locals"
				render()

initSession = (ses, prefs) ->
	if not ses.account
		# New sesion: set anon to session and continue
		ses.account = anon: ++indexCount, group: 'signon'
		prefs.autofocus = 'signon'
		log "New user: " + ses.account.anon
	look ses.account, "Session Account:"

app.post "/balance", (req, res) ->
	debugger
	prefs = preferences req
	ses = req.session
	initSession(ses, prefs)
	look p = req.body, "The form sent to balance:"
	# If not insert the form sends an id that we convert to an ObjectID and set to p.key
	id = dislodge p, 'id'
	look (p.key = _id : new ObjectID id), "Key definition:" if id
	action = p.action
	doSignoff = ->
		prefs.autofocus = "signon"
		ses.destroy()
		res.send('')
	if ses.account
		p.account = ses.account._id
	validate p, ses, (err, row) ->
		if err
			res.send("Validation Error: " + log err)
		else
			prefs.autofocus = row.group
			if row.group == 'signon'
				signon row, ses, (err, user) ->
					if err
						err = "Signon Error: " + err
						res.send(err)
					else if action == 'delete'
						doSignoff()
					else
						visible prefs, false, 'signon'
						visible prefs, true, 'bank'
						visible prefs, true, 'expense'
						visible prefs, true, 'totals'
						prefs.autofocus = 'expense'
						res.send('')
			else if row.group == "signoff"
				doSignoff()
			else
				persist row, MONEY, action, (err, docs) ->
					log err if err
					res.send(if err then "Data Error: " + err else '')

app.post "/toggle", (req, res) ->
	p = req.body
	visible preferences(req), p.visible == 'true', p.name
	res.send("Saved " + p.name + " to " + preferences(req).style[p.name] + " in session");

visible = (prefs, visible, name) ->
	if visible
		dislodge prefs.style, name
	else
		prefs.style[name] = "display: none;"

init = (obj, p, as) ->
	property = obj[p]
	if not property
		property = if as? then as else {}
		obj[p] = property
	property

preferences = (req) ->
	prefs = init req.session, 'preferences'
	init prefs, 'style'
	prefs

app.listen(8743)

# Structure {group: {field: {needs: needs}}}
validation =
	signon :
		user : {name: "Username", required: true}
		pass : {name: "Password", required: true}
	bank :
		name		: {name: "Name",		required: true}
		balance : {name: "Balance", required: true, beFloat: true}
		epoch		: {name: "Date",		required: true,	 beInt: true}
	expense :
		name			: {name: "Name",			 required: true}
		amount		: {name: "Amount",		 required: true, beFloat: true}
		fromEpoch : {name: "From Date",	 required: true,	 beInt: true}
		uptoEpoch : {name: "Upto Date",	 required: false,	 beInt: true}

typeCheck = (row) ->
	messages = []
	for group, fields of validation
		if row.group == group and row.action != 'delete'
			for field, needs of fields
				row[field] = row[field].trim() if row[field] and row[field] instanceof String
				if needs.required and not row[field]
					messages.push "The " + needs.name + " is a required field"
				if needs.beFloat and not makeFloat row, field
					messages.push "The " + needs.name + " must be numeric"
				else if needs.beInt and not makeInt row, field
					messages.push "The " + needs.name + " must be a whole number"
	messages


delimit = (del, list) ->
	str = ""
	d = ""
	for item in list
		str += d + item
		d = del
	str

validate = (row, ses, callback) ->
	delay = false
	if not err = delimit ", ", typeCheck row
		row.unique = {account: row.account}
		if row.group == 'signon'
			row.unique = user: row.user
			if row.action != 'add'
				row.unique._id = $ne : new ObjectID row.account
			look row, "Validating Signon: "
		else if ses.account.anon and not row.account
			delay = true
			tempSignon ses, (err, account) ->
				if err
					callback err
				else
					# Not sure if this is the 'right' way to get ObjectID string
					row.account = account._id.toString()
					row.unique.account = row.account
					look row, "New user with account: " + row.account + " Revalidating row: "
					validate row, ses, callback
		else if row.group == 'bank'
			if row.action != 'add'
				row.unique._id = $ne : row.key._id
			row.unique.name = row.name
		else if row.group == 'expense'
			row.unique = name : row.name, epoch : row.fromEpoch
			if row.action != 'add'
				row.unique._id = $ne : row.key._id
	if not delay
		callback err, row

###
Signon Action
###

tempSignon = (ses, callback) ->
	dirty = {anon: ses.account.anon}
	persist dirty, USER, 'add', (err, docs) ->
		if err or docs.legnth < 1
			callback "Sorry, there was a problem: " + (err or "nothing saved")
		else
			ses.account = docs[0]
			callback false, ses.account

signon = (row, ses, callback) ->
	register = dislodge(row, 'register')
	findOne {user: row.user, pass: row.pass}, USER, (err, account) ->
		if account
			ses.account = account;
			ses.account.group = 'signon'
			callback null, account.user
		else if register and register == 'on'
			dislodge row, 'group'
			dislodge row, 'account'
			action = dislodge row, 'action'
			if ses.account._id
				row._id = new ObjectID ses.account._id
				row.key = {_id: row._id}
			look row, "About to " + action + " registration for user:"
			persist row, USER, action, (err, docs) ->
				if err || err instanceof Error
					callback err
				else if action == 'delete'
					callback null
				else
					signon row, ses, callback
		else
			callback "Username password combination incorrect"

###
Summary Logic
###
defineTotals = (locals) ->
	currentBank = max(locals.bank, 'epoch')
	if currentBank
		after = dateOf currentBank.epoch;
		bank = balance: sum locals.bank, 'balance'
		locals.totals = [bank]
		total = 0
		for i in [1..50]
			before = nextIncrement after, i
			data = sumEachExpense locals.expense, after, before
			if data.sum != 0
				total += data.sum
				weekNext =
					payment: tidyFloat data.sum * -1
					balance: tidyFloat total + bank.balance
					date: formatDate after
					items: data.items
				locals.totals.push(weekNext)
			after = before

nextIncrement = (after, i) ->
	next = dateOf after
	if i < 14
		next.addDays 1
	else if i < 21
		next.addWeeks 1
	else if i < 41
		next.addMonths 1
	else
		next.addYears 1

pad = (str, length) ->
	str = String(str);
	while (str.length < length)
		str = '0' + str
	str

dateOf = (epoch) ->
	if epoch then new Date(if epoch instanceof Date then epoch else parseInt(epoch) * 1000) else null

tidyFloat = (float) ->
	Math.round(float * 100) / 100

formatDate = (epoch) ->
	d = new Date(if epoch instanceof Date then epoch else epoch * 1000)
	pad(d.getDate(), 2) + ' ' + d.getMonthAbbr() + ' ' + d.getFullYear()

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

sumEachExpense = (expenses, after, before) ->
	###
	expense: Expense
	after: Date
	before: Date
	result: Integer
	###
	total = 0
	items = []
	for expense in expenses
		###
		TODO It would be helpful to have a mechanism to record how many
		occurances of each expense there are. This needs to be done in
		sumExpense but we cannot attach it to the expense itself. Clone
		or create a new object that records the expense and the number
		of occurances.
		###
		data = sumExpense expense, after, before
		if data.sum != 0
			total += data.sum
			items.push {expense: expense, occurances: data.occurances}
	sum: tidyFloat(total), items: items

sumExpense = (expense, after, before) ->
	###
	After and Before are both javascript Date objects. Expense must implement:
		.frequency: String - Either day, week, fortnight, month, quarter, half, year
		.amount: Float - The amount for each frequency
		.fromEpoch: Int - The amount the expense started. Epoch is seconds since 1970 (not millis)
		.uptoEpoch: Int - (optional) When the frequency of the expense terminates (including)
		.type: String - If expense then amount is made negative (otherwise considered income)
	###
	total = 0
	occurances = 0
	next = dateOf expense.fromEpoch
	upto = dateOf expense.uptoEpoch
	while next and next < before and (!upto or next <= upto)
		if next >= after
			total += negafyExpense expense
			occurances++;
		switch expense.frequency
			when "day" then next.addDays(1)
			when "weekday" then addWeekDays(next, 1)
			when "week" then next.addWeeks(1)
			when "fortnight" then next.addWeeks(2)
			when "month" then next.addMonths(1)
			when "quarter" then next.addMonths(3)
			when "half" then next.addMonths(6)
			when "year" then next.addYears(1)
			else next = false
	sum: tidyFloat(total), occurances: occurances

addWeekDays = (date, n) ->
	date.addDays(n)
	while 0 >= date.getDay() or date.getDay() >= 6
		date.addDays(n)

negafyExpense = (expense) ->
	negafy expense, 'type', 'expense', expense.amount

sum = (list, p, negKey, negVal, epoch) ->
	balance = 0
	for obj in list
		amount = parseFloat(obj[p])
		if !isNaN(amount)
			balance += negafy obj, negKey, negVal, amount
	tidyFloat balance

negafy = (obj, negKey, negVal, amount) ->
	if negKey and negVal and obj[negKey] == negVal
		amount * -1
	else
		amount

###
Strings
###
didFloat = (obj, property) ->
	obj and property and obj[property] and makeFloat obj, property

makeFloat = (obj, property) ->
	ok = true
	if obj[property]
		ok = !isNaN obj[property]
		if ok
			obj[property] = parseFloat(obj[property])
	ok

didInt = (obj, property) ->
	obj and property and obj[property] and makeInt obj, property

makeInt = (obj, property) ->
	ok = true
	if obj[property]
		ok = !isNaN obj[property]
		if ok
			obj[property] = parseInt(obj[property])
	ok

###
Objects
###

dislodge = (obj, property) ->
	value = obj[property]
	delete obj[property]
	value


###
Data
###
findOne = (key, table, callback) ->
	look key, "Looking in " + table + " for: "
	db.collection table, (err, c) ->
		callback(err, c) if err instanceof Error
		c.findOne key, (err, doc) ->
			callback(err, doc)

list = (key, table, callback) ->
	db.collection table, (err, c) ->
		callback(err, c) if err instanceof Error
		c.find key, (err, cursor) ->
			callback(err, cursor) if err instanceof Error
			cursor.toArray (err, array) ->
				callback(err, array)

ensureUnique = (connection, qualifier, callback) ->
	if qualifier
		look qualifier, "Qualifier: "
		connection.count [qualifier], (err, count) ->
			callback(err, count)
	else
		callback(null, 0)

persist = (row, table, action, callback) ->
	rowAction = dislodge row, 'action'
	log "Passed action: " + action + ", Row action: " + rowAction if rowAction and rowAction != action
	look row, "About to " + action + " in " + table + ":"
	key = dislodge row, 'key'
	look key, "Key used to determine which doc to " + action + ":"
	unique = dislodge row, 'unique'
	look unique, "Will not update if this (unique search) exists:"
	final = (err, docs) ->
		if err
			look err, "Error in Persisting:"
			look row, "Failed to save:"
		else
			look docs, "Saved:"
		callback(err, docs) if callback
	db.collection table, (err, c) ->
		callback(err.message) if err instanceof Error
		if action == 'add'
			ensureUnique c, unique, (err, count) ->
				if err instanceof Error
					callback err.message
				else if count < 1
					c.insert [row], final
				else
					callback "Found " + count + " duplicate key on insert"
		else if action == 'change'
			look key, "Type of key: " + typeof key
			look key.id, "Type of id: " + (typeof key.id) if key.id
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

###
Debug
###
log = util.log
look = util.look
