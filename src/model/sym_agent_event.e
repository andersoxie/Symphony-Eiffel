note
	description: "Structured event emitted by the Codex app-server client."

class
	SYM_AGENT_EVENT

create
	make

feature {NONE} -- Initialization

	make (a_event: READABLE_STRING_GENERAL; a_pid: detachable READABLE_STRING_GENERAL; a_message: detachable READABLE_STRING_GENERAL)
		require
			event_present: not a_event.is_empty
		do
			event := a_event.to_string_32.twin
			timestamp := clock.iso_8601_now
			if attached a_pid as v then codex_app_server_pid := v.to_string_32.twin end
			if attached a_message as v then message := v.to_string_32.twin end
		ensure
			event_set: event.same_string_general (a_event)
			timestamp_shape: timestamp.count = 24 and then timestamp [11] = 'T' and then timestamp [24] = 'Z'
			pid_set:
				(attached a_pid as source and then attached codex_app_server_pid as stored and then stored.same_string_general (source)) or else
				(a_pid = Void and then codex_app_server_pid = Void)
			message_set:
				(attached a_message as source and then attached message as stored and then stored.same_string_general (source)) or else
				(a_message = Void and then message = Void)
			usage_initially_zero: input_tokens = 0 and then output_tokens = 0 and then total_tokens = 0
			no_initial_rate_limits: rate_limits = Void
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
		require
			input_non_negative: a_input >= 0
			output_non_negative: a_output >= 0
			total_non_negative: a_total >= 0
		do
			input_tokens := a_input
			output_tokens := a_output
			total_tokens := a_total
		ensure
			input_set: input_tokens = a_input
			output_set: output_tokens = a_output
			total_set: total_tokens = a_total
		end

	set_rate_limits (a_value: JSON_OBJECT)
		do
			rate_limits := a_value
		ensure
			rate_limits_set: rate_limits = a_value
		end

feature {NONE} -- Helper

	clock: SYM_CLOCK once create Result end

end
