$(document).ready ->
	$("dt").dblclick ->
		toggleDD($(this).next())

	$("div.expander").click ->
		toggleDD($(this).parent().next());

	$("input#register").click ->
		$(this).parent().next().val(if $(this).is(":checked") then "Register" else "Sign On")

	$("thead").dblclick ->
		$(this).next().toggle("fast")

	$("form").submit ->
		submitForm(this)

	$("button.action").click ->
		data =
			submit: $(this).val()
			action: $(this).attr("name")
		copyDataToAction data, this

	$("input#expensesPaid").click ->
		log checked = $(this).is(":checked")
		for i in [2..3]
			$("#totals tr td:nth-child(" + i + ")").toggle()

	$(".hover").hover (e) ->
		$(this).children().first().show()
	, (e) ->
		$(this).children().first().hide()

	$("table.browse").tablesorter()

	$(".date-picker").datepicker
		onSelect: (dateText, inst) ->
			name = this.name
			option = if name == "fromDate" then "minDate" else if name = "uptoDate" then "maxDate"
			if option
				log "Option: " + option + ", This name: " + this.name
				instance = $( this ).data "datepicker"
				format = instance.settings.dateFormat or $.datepicker._defaults.dateFormat
				date = $.datepicker.parseDate format, dateText, instance.settings
				tbody = $(this).parent().parent().parent()
				log other = $(tbody).find(".date-picker").not(this), "The other date picker in this tbody:"
				other.datepicker("option", option, date)
			epoch = $.datepicker.formatDate("@", $(this).datepicker('getDate')) / 1000
			hidden = log $(this).next(), "Setting hidden date value to: " + epoch
			$(this).next().val(epoch);

	this

toggleDD = (dd) ->
	visible = dd.is(":hidden")
	dd.toggle()
	dt = dd.prev();
	expander = $("div.expander", dt)
	expander.text(if expander.text() == '+' then '-' else '+')
	$.post "/toggle", {name: dt.attr("name"), visible: visible}, (err) ->
		log err if err

submitForm = (form) ->
	try
		inputData = $(form).find(":input").serializeArray();
		log inputData, "All form data"
		$.post "/balance", inputData, (err) ->
			if err && err != ''
				alert err
			else
				window.location.href = window.location.pathname
		false
	catch e
		log e
		false

###
# Finds the hidden inputs of the change or delete buttons based on a convention
# of keeping the inputs in the last td of the catalog table.
###
findModifyActionHiddenInputs = (clicked) ->
	# button.td.tr.allTds.lastTd.hiddenInputs
	$(clicked).parent().parent().children().last().children()

copyDataToAction = (data, clicked) ->
	mapHidden(data, findModifyActionHiddenInputs clicked)
	log form = "form#" + data.group, "Group"
	$(form)[0].reset() if data.action == 'add'
	mergeAttributes data, $(":input", form)
	log tbody = $("tbody", form).show()
	$(":input", form).first().focus()
	$(".register-box").hide() if data.group == 'signon'

mapHidden = (data, hiddens) ->
	hiddens.each (i, input) ->
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
	text

