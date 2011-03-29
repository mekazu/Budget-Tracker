$(document).ready ->
	$("#more").click ->
		tbody = $("tbody#bank-details");
		tr = tbody.children().last().clone(true).appendTo(tbody)
		tr.find("input").attr("value", "")
		tr.find(".less").show()

	$(".less").click ->
		# removes this > td > tr
		$(this).parent().parent().remove()

	$("#bank").submit ->
		balance = $(this).find(":input").serializeArray();
		log balance, "all data"
		$.post "/balance", balance, (result) ->
			alert(result);
		false

	$(".change").click ->
		tds = $(this).parent().children()
		inputs = $(":input", "#bank")
		tds.each (i, td) ->
			name = $(td).attr("name")
			value = $(td).text();
			if name
				log "Name: " + name + ", Value: " + value
				inputs.each (j, input) ->
					inputName = $(input).attr("name")
					if inputName == "action"
						$(input).attr("value", "change")
					if inputName == name
						$(input).attr("value", value)

	this
showValues = ->
	fields = $("#bank :input").serializeArray()
	log(fields)
	$("#results").empty()
	$.each fields, (i, field) ->
		$("#results").append(field.value + " ")


log = (text, note) ->
	if console && console.log
		if note
			log note
		console.log text
		if text.length && text.jQuery
			log text[0]

