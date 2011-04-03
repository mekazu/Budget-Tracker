$(document).ready ->
	$("dt").dblclick ->
		$(this).next().toggle("fast")

	$("thead").dblclick ->
		$(this).next().toggle("fast")

	$("form").submit ->
		submitForm(this)

	$(".change").click ->
		data = {}
		data.action = "change"
		data.submit = "Update"
		log $(this).attr("name")
		copyDataToAction data, this

	$(".delete").click ->
		data = {}
		data.action = "delete"
		data.submit = "Delete"
		copyDataToAction data, this

	$(".new").click ->
		data = {}
		data.action = "new"
		data.submit = "Save"
		copyDataToAction data, this

	$(".date-picker").datepicker
		onSelect: (dateText, inst) ->
			epoch = $.datepicker.formatDate("@", $(this).datepicker('getDate')) / 1000
			hidden = log $(this).next(), "Setting hidden date value to: " + epoch
			$(this).next().val(epoch);

	this

submitForm = (form) ->
	try
		inputData = $(form).find(":input").serializeArray();
		log inputData, "All form data"
		$.post "/balance", inputData, (err) ->
			if err && err != ''
				alert err
			else
				log "Got response from form submit. Reloading."
				window.location = window.location
		false
	catch e
		log e
		false

copyDataToAction = (data, clicked) ->
	mapHidden(data, $(clicked).parent().parent().children().last().children())
	group = "#" + data.group
	mergeAttributes data, $(":input", group)
	log tbody = $("tbody", group).show()

mapHidden = (data, hidden) ->
	hidden.each (i, input) ->
		if name = $(input).attr("name")
			if !data[name]
				data[name] = $(input).attr("value")

mergeAttributes = (from, inputs) ->
	log from, "Merging: from"
	log inputs, "Merging: to"
	inputs.each (i, input) ->
		for key, value of from
			if $(input).attr("name") == key
				log "Merging key: " + key + ", value: " + value
				$(input).val(value)
				if $(input).prev().hasClass("hasDatepicker")
					epoch = parseInt(value)
					if !isNaN epoch
						raw = $.datepicker.parseDate("@",epoch * 1000)
						$(input).prev().datepicker('setDate', raw)

log = (text, note) ->
	if console && console.log
		if note
			log note
		console.log text
		if text.length && text.jQuery
			log text[0]

