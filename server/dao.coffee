mongodb = require('mongodb')
util = require('./util')

# Classes
Database = (host, port, database) ->
	this.db = new mongodb.Db(database, new mongodb.Server(host, port, {auto_reconnect: true}, {}))
	this.db.open ->
		util.log "MongoDB Connected: " + host + ", " + port + ", " + database

db = new Database("localhost", 27017, "budget").db

###
# Exports
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

max = (field, table, callback) ->
	db.collection table, (err, c) ->
		callback(err, c) if err instanceof Error
		search = {}
		search[field] = '$gt': -1
		options =
			limit: 1
			sort: [[field, 'desc']]
		c.find search, options, (err, cursor) ->
			cursor.toArray (err, array) ->
				found = if array.length > 0 then array[0] else null
				callback err, found

ensureUnique = (connection, qualifier, callback) ->
	if qualifier
		look qualifier, "Qualifier: "
		connection.count [qualifier], (err, count) ->
			callback(err, count)
	else
		callback(null, 0)

persist = (p, table, callback) ->
	look p.doc, "About to " + p.action + " in " + table + ":"
	look p.key, "Key used to determine which doc to " + p.action + ":"
	look p.unique, "Will not update if this (unique search) exists:"
	final = (err, docs) ->
		if err
			look err, "Error in Persisting:"
			look p, "Failed to save:"
		else
			look docs, "Saved:"
		callback(err, docs) if callback
	db.collection table, (err, c) ->
		callback(err.message) if err instanceof Error
		if p.action == 'add'
			ensureUnique c, p.unique, (err, count) ->
				if err instanceof Error
					callback err.message
				else if count < 1
					c.insert [p.doc], final
				else
					callback "Found " + count + " duplicate key on insert"
		else if p.action == 'change'
			look p.key, "Type of key: " + typeof p.key
			look p.key.id, "Type of id: " + (typeof p.key.id) if p.key.id
			c.findOne p.key, (err, doc) ->
				if look doc, "Before Update:"
					ensureUnique c, p.unique, (err, count) ->
						if err instanceof Error
							callback err.message
						if count < 1
							c.update p.key, p.doc, {safe: true}, final
						else
							callback "Found " + count + " duplicate key on insert"
				else
					callback("Could not find the doc to update", null);
		else if p.action == 'replace'
			c.findOne p.key, (err, doc) ->
				if look doc, "Before Replace:"
					p.doc._id = doc._id
					c.update p.key, p.doc, {safe: true}, final
				else
					callback("Could not find the doc to update", null);
		else if p.action == 'delete'
			c.findOne p.key, (err, doc) ->
				if look doc, "Before delete"
					c.remove doc, {safe: true}, final
				else
					callback("Could not find the doc to delete", null);
		else
			callback("Action: " + p.action + " not understood.");

###
# Debug
###
log = util.log
look = util.look

exports.findOne      = findOne
exports.list         = list
exports.ensureUnique = ensureUnique
exports.persist      = persist
exports.max					 = max

