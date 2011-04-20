sys = require('sys')

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

exports.trim = trim
exports.log  = log
exports.look = look

