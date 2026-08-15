note
	description: "Structured event emitted by the Codex app-server client."

class
	SYM_AGENT_EVENT

create
	make

feature {NONE} -- Initialization

	make (a_event: READABLE_STRING_GENERAL; a_pid: detachable READABLE_STRING_GENERAL; a_message: detachable READABLE_STRING_GENERAL)
		do
			event := a_event.to_string_32.twin
			timestamp := clock.iso_8601_now
			if attached a_pid as v then codex_app_server_pid := v.to_string_32.twin end
			if attached a_message as v then message := v.to_string_32.twin end
		end

feature -- Access

	event: STRING_32

	timestamp: STRING_8

	codex_app_server_pid: detachable STRING_32

	message: detachable STRING_32

	input_tokens: INTEGER_64

	output_tokens: INTEGER_64

	total_tokens: INTEGER_64

	rate_limits: detachable JSON_OBJECT

	set_usage (a_input, a_output, a_total: INTEGER_64)
		do
			input_tokens := a_input
			output_tokens := a_output
			total_tokens := a_total
		end

	set_rate_limits (a_value: JSON_OBJECT)
		do
			rate_limits := a_value
		end

feature {NONE} -- Helper

	clock: SYM_CLOCK once create Result end

end
