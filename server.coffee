# Require
express			= require('express')
sys					= require('sys')
dateUtils		= require('date-utils')
mongodb			= require('mongodb')
util				= require('./server/util')
dao					= require('./server/dao')
secret			= require('./server/secret')

# Classes
ObjectID = mongodb.BSONNative.ObjectID

# Final
MONEY 			= "money"
USER				= "user"

# Global
indexCount = 0

###
# Web Server
###
app = express.createServer()
app.configure ->
	app.use express.static(__dirname + '/public')
	app.use express.bodyParser()
	app.use express.cookieParser()
	app.use express.session(secret: secret.session)

app.get '/', (req, res) ->
	# Prefs are stored in session and relayed to locals
	prefs = preferences req
	ses = req.session
	initSession ses, prefs
	locals = {prefs: prefs, log: log, signon: [ses.account]}
	render = ->
		res.render 'index.jade', {title: "Budget Diary", locals: locals}
	if ses.account.anon and not ses.account._id
		# Unregistered user who hasn't done anything yet
		prefs.anon = ses.account.anon
		render()
	else
		# User with something to display (not ses.account.anon or ses.account._id)
		prefs.user = ses.account.user if ses.account.user # Registered User
		dao.list {group: 'bank', account: ses.account._id}, MONEY, (err, results) ->
			locals.bank = results
			dao.list {group: 'expense', account: ses.account._id}, MONEY, (err, results) ->
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
	prefs = preferences req
	ses = req.session
	initSession(ses, prefs)
	look p = req.body, "The form sent to balance:"
	# If not insert the form sends an id that we convert to an ObjectID and set to p.key
	look (p.key = _id : new ObjectID p.id), "Key definition:" if p.id
	doSignoff = ->
		prefs.autofocus = "signon"
		ses.destroy()
		res.send('')
	if ses.account
		p.account = ses.account._id
	validate p, ses, (err, prm) ->
		if err
			res.send("Validation Error: " + log err)
		else
			prefs.autofocus = prm.group
			if prm.group == 'signon'
				signon prm, ses, (err, user) ->
					if err
						err = "Signon Error: " + err
						res.send(err)
					else if p.action == 'delete'
						doSignoff()
					else
						visible prefs, false, 'signon'
						visible prefs, true, 'bank'
						visible prefs, true, 'expense'
						visible prefs, true, 'totals'
						prefs.autofocus = 'expense'
						res.send('')
			else if prm.group == "signoff"
				doSignoff()
			else
				dao.persist prm, MONEY, (err, docs) ->
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

preferences = (req) ->
	prefs = init req.session, 'preferences'
	init prefs, 'style'
	prefs

app.listen(8743)

###
# Objects
###
init = (obj, p, as) ->
	property = obj[p]
	if not property
		property = if as? then as else {}
		obj[p] = property
	property

delimit = (del, list) ->
	str = ""
	d = ""
	for item in list
		str += d + item
		d = del
	str

###
# Validation
# Structure: {group: {field: {needs: needs}}}
###
validation =
	signon :
		user : {name: "Username", required: true}
		pass : {name: "Password", required: true, encrypt: true}
		anon : {name: "Guest"}
	bank :
		name		: {name: "Name",		required: true}
		balance : {name: "Balance", required: true, beFloat: true}
		epoch		: {name: "Epoch",		required: true,	 beInt: true}
		date    : {name: "Date",    required: true}
		account : {name: "Account", required: false}
		group   : {name: "Group",   required: true}
	expense :
		name			: {name: "Name",			 required: true}
		amount		: {name: "Amount",		 required: true, beFloat: true}
		fromDate  : {name: "From Date"}
		uptoDate  : {name: "Upto Date"}
		fromEpoch : {name: "From Epoch", required: true,   beInt: true}
		uptoEpoch : {name: "Upto Epoch",    beInt: true}
		account   : {name: "Account",    required: false}
		frequency : {name: "Frequency",  required: true}
		group     : {name: "Group",      required: true}
		type      : {name: "Type",       required: true}

typeCheck = (prm) ->
	messages = []
	prm.doc = {}
	for group, fields of validation
		if prm.group == group and prm.action != 'delete'
			for field, needs of fields
				prm[field] = prm[field].trim() if prm[field] and prm[field] instanceof String
				if needs.required and not prm[field]
					messages.push "The " + needs.name + " is a required field"
				if needs.beFloat and not makeFloat prm, field
					messages.push "The " + needs.name + " must be numeric"
				else if needs.beInt and not makeInt prm, field
					messages.push "The " + needs.name + " must be a whole number"
				if needs.encrypt
					prm[field] = util.encrypt prm[field]
				prm.doc[field] = prm[field]
	messages

validate = (prm, ses, callback) ->
	if err = delimit ", ", typeCheck prm
		callback err
	else if prm.group != 'signon' and ses.account.anon and not prm.account
		tempSignon ses, (err, account) ->
			return callback err if err
			# Not sure if this is the 'right' way to get ObjectID string
			prm.account = account._id.toString()
			look prm, "New user with account: " + prm.account + " Revalidating prm: "
			validate prm, ses, callback
	else
		switch prm.group
			when 'signon'  then prm.unique = user: prm.user
			when 'bank'    then prm.unique = user: prm.user, account: prm.account
			when 'expense' then prm.unique = name: prm.name, account: prm.account, epoch: prm.fromEpoch
		if prm.action != 'add'
			switch prm.group
				when 'signon'  then prm.unique._id = $ne : new ObjectID prm.account
				when 'bank'    then prm.unique._id = $ne : prm.key._id
				when 'expense' then prm.unique._id = $ne : prm.key._id
		callback err, prm

###
# Signon
###
tempSignon = (ses, callback) ->
	dirty = {doc: {anon: ses.account.anon}, action: 'add'}
	dao.persist dirty, USER, (err, docs) ->
		if err or docs.legnth < 1
			callback "Sorry, there was a problem: " + (err or "nothing saved")
		else
			ses.account = docs[0]
			callback false, ses.account

###
# If the user makes a mistake by logging in when the register checkbox
# has already been checked then they are logged in if the password is correct.
###
signon = (p, ses, callback) ->
	register = dislodge p, 'register'
	dao.findOne {user: p.user, pass: p.pass}, USER, (err, account) ->
		if account
			ses.account = account;
			ses.account.group = 'signon' #
			callback null, account.user
		else if register and register == 'on'
			if ses.account._id
				p._id = new ObjectID ses.account._id
				p.key = {_id: p._id}
			look p, "About to " + p.action + " registration for user:"
			dao.persist p, USER, (err, docs) ->
				if err || err instanceof Error
					callback err
				else if p.action == 'delete'
					callback null
				else
					signon p, ses, callback
		else
			callback "Username password combination incorrect"

###
# Summary Logic
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

###
# expense: Expense
# after: Date
# before: Date
# result: Integer
###
sumEachExpense = (expenses, after, before) ->
	total = 0
	items = []
	for expense in expenses
		data = sumExpense expense, after, before
		if data.sum != 0
			total += data.sum
			items.push {expense: expense, occurances: data.occurances}
	sum: tidyFloat(total), items: items

###
# after: Date
# before: Date
# expense must implement:
# 	.frequency: String - Either day, week, fortnight, month, quarter, half, year
# 	.amount: Float - The amount for each frequency
# 	.fromEpoch: Int - The amount the expense started. Epoch is seconds since 1970 (not millis)
# 	.uptoEpoch: Int - (optional) When the frequency of the expense terminates (including)
# 	.type: String - If expense then amount is made negative (otherwise considered income)
###
sumExpense = (expense, after, before) ->
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
# Strings
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
# Objects
###
dislodge = (obj, property) ->
	value = obj[property]
	delete obj[property]
	value


###
# Debug
###
log = util.log
look = util.look
