sys    = require('sys')
secret = require('./secret')
crypto = require('crypto')

###
# Strings
###
trim = (string) ->
  string.replace(/^\s+|\s+$/g, '') ;

String::trim = ->
  trim(this)

log = (text, note) ->
	log note if note
	sys.puts text
	text

look = (obj, note) ->
	log note if note
	sys.puts sys.inspect obj
	obj

###
# Password Encryption
###
encrypt = (text) ->
	cipher = crypto.createCipher('aes-256-cbc', secret.newKey)
	log "Encrypting " + text + ":"
	log cipher.update(text, 'utf8', 'hex') + cipher.final('hex')

decrypt = (crypted) ->
	decipher = crypto.createDecipher('aes-256-cbc', secret.oldKey)
	log "Decrypting " + crypted + ":"
	log decipher.update(crypted, 'hex', 'utf8') + decipher.final('utf8')

exports.trim = trim
exports.log  = log
exports.look = look
exports.encrypt = encrypt
exports.decrypt = decrypt
