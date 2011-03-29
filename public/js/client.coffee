$(document).ready ->
	$("#bank").submit ->
		balance = $(this).find(":input").serializeArray();
		log balance, "all data"
		$.post "/balance", balance, (err) ->
			if err && err != ''
				alert err
			else
				window.location.href = window.location.href
		false

	$(".change").click ->
		data = {}
		data.action = "change"
		data.submit = "Update"
		copyDataToAction data, this

	$(".delete").click ->
		data = {}
		data.action = "delete"
		data.submit = "Delete"
		copyDataToAction data, this

	copyDataToAction = (data, clicked) ->
		mapHidden(data, $(clicked).parent().parent().children().last().children())
		mergeAttributes(data, $(":input", "#bank"))
	this

mapHidden = (data, hidden) ->
	hidden.each (i, input) ->
		if name = $(input).attr("name")
			if !data[name]
				data[name] = $(input).attr("value")

mergeAttributes = (from, inputs) ->
	log from, "Merging"
	inputs.each (i, input) ->
		for key, value of from
			if $(input).attr("name") == key
				log "Merging key: " + key + ", value: " + value
				$(input).attr("value", value)

log = (text, note) ->
	if console && console.log
		if note
			log note
		console.log text
		if text.length && text.jQuery
			log text[0]

