note
	description: "Thread-safe JSON-lines logger with stdout and optional append-only file sinks."

class
	SYM_LOGGER

create
	make,
	make_stdout

feature {NONE} -- Initialization

	make (a_log_file: detachable PATH)
			-- Log to stdout and, when supplied, append to `a_log_file'.
		do
			log_file_path := a_log_file
			create clock
			create write_lock.make
		end

	make_stdout
			-- Log only to stdout.
		do
			make (Void)
		end

feature -- Levels

	log_debug (a_event, a_message: READABLE_STRING_GENERAL; a_context: detachable SYM_LOG_CONTEXT)
		do
			log (debug_level, a_event, a_message, a_context, Void)
		end

	log_debug_with_fields (a_event, a_message: READABLE_STRING_GENERAL;
		a_context: detachable SYM_LOG_CONTEXT; a_fields: detachable JSON_OBJECT)
		do
			log (debug_level, a_event, a_message, a_context, a_fields)
		end

	info (a_event, a_message: READABLE_STRING_GENERAL; a_context: detachable SYM_LOG_CONTEXT)
		do
			log (info_level, a_event, a_message, a_context, Void)
		end

	info_with_fields (a_event, a_message: READABLE_STRING_GENERAL;
		a_context: detachable SYM_LOG_CONTEXT; a_fields: detachable JSON_OBJECT)
		do
			log (info_level, a_event, a_message, a_context, a_fields)
		end

	warning (a_event, a_message: READABLE_STRING_GENERAL; a_context: detachable SYM_LOG_CONTEXT)
		do
			log (warning_level, a_event, a_message, a_context, Void)
		end

	warning_with_fields (a_event, a_message: READABLE_STRING_GENERAL;
		a_context: detachable SYM_LOG_CONTEXT; a_fields: detachable JSON_OBJECT)
		do
			log (warning_level, a_event, a_message, a_context, a_fields)
		end

	error (a_event, a_message: READABLE_STRING_GENERAL; a_context: detachable SYM_LOG_CONTEXT)
		do
			log (error_level, a_event, a_message, a_context, Void)
		end

	error_with_fields (a_event, a_message: READABLE_STRING_GENERAL;
		a_context: detachable SYM_LOG_CONTEXT; a_fields: detachable JSON_OBJECT)
		do
			log (error_level, a_event, a_message, a_context, a_fields)
		end

feature -- Logging

	log (a_level, a_event, a_message: READABLE_STRING_GENERAL;
		a_context: detachable SYM_LOG_CONTEXT; a_fields: detachable JSON_OBJECT)
			-- Emit one structured event. Reserved fields cannot be overridden by `a_fields'.
		require
			level_present: not a_level.is_empty
			event_present: not a_event.is_empty
		local
			l_line: STRING_8
		do
			l_line := event_line (a_level, a_event, a_message, a_context, a_fields)
			l_line.append_character ('%N')
			emit_line (l_line)
		end

	redacted_fields (a_fields: JSON_OBJECT): JSON_OBJECT
			-- Deep copy of `a_fields' with values below secret-looking keys redacted.
		do
			Result := sanitized_object (a_fields)
		end

	is_secret_key (a_key: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_key' a known or conventionally named secret field?
		do
			Result := secret_keys.is_secret_key (a_key)
		end

feature -- Status

	log_file_path: detachable PATH
			-- Optional append-only sink.

	file_sink_failed: BOOLEAN
			-- Has the file sink failed and been disabled?

	has_file_sink: BOOLEAN
		do
			Result := attached log_file_path
		end

feature {NONE} -- Event construction

	event_line (a_level, a_event, a_message: READABLE_STRING_GENERAL;
		a_context: detachable SYM_LOG_CONTEXT; a_fields: detachable JSON_OBJECT): STRING_8
		local
			o, l_context, l_fields: JSON_OBJECT
		do
			create o.make_with_capacity (8)
			put_string (o, "timestamp", utc_timestamp)
			put_string (o, "level", a_level)
			put_string (o, "event", a_event)
			put_string (o, "message", a_message)

			if attached a_context as ctx then
				l_context := ctx.as_json
			else
				create l_context.make_with_capacity (3)
				put_null (l_context, "issue_id")
				put_null (l_context, "issue_identifier")
				put_null (l_context, "session_id")
			end
			across l_context as entry loop
				o.put (entry.item, entry.key)
			end

			if attached a_fields as f then
				l_fields := sanitized_object (f)
			else
				create l_fields.make_empty
			end
			put_value (o, "fields", l_fields)
			Result := o.representation
		ensure
			one_physical_line: not Result.has ('%N') and not Result.has ('%R')
		end

	put_string (a_object: JSON_OBJECT; a_key: READABLE_STRING_8;
		a_value: READABLE_STRING_GENERAL)
		local
			k, v: JSON_STRING
		do
			create k.make_from_string (a_key)
			create v.make_from_string_general (a_value)
			a_object.put (v, k)
		end

	put_null (a_object: JSON_OBJECT; a_key: READABLE_STRING_8)
		local
			k: JSON_STRING
		do
			create k.make_from_string (a_key)
			a_object.put (Void, k)
		end

	put_value (a_object: JSON_OBJECT; a_key: READABLE_STRING_8; a_value: JSON_VALUE)
		local
			k: JSON_STRING
		do
			create k.make_from_string (a_key)
			a_object.put (a_value, k)
		end

	utc_timestamp: STRING_8
			-- Current UTC instant in RFC 3339 format with millisecond precision.
		local
			now: DATE_TIME
			milliseconds: INTEGER
		do
			now := clock.now_utc
			milliseconds := ((now.fine_second - now.second) * 1000.0).truncated_to_integer.max (0).min (999)
			create Result.make (24)
			append_padded_integer (Result, now.year, 4)
			Result.append_character ('-')
			append_padded_integer (Result, now.month, 2)
			Result.append_character ('-')
			append_padded_integer (Result, now.day, 2)
			Result.append_character ('T')
			append_padded_integer (Result, now.hour, 2)
			Result.append_character (':')
			append_padded_integer (Result, now.minute, 2)
			Result.append_character (':')
			append_padded_integer (Result, now.second, 2)
			Result.append_character ('.')
			append_padded_integer (Result, milliseconds, 3)
			Result.append_character ('Z')
		ensure
			rfc3339_shape: Result.count = 24 and then Result [11] = 'T' and then Result [24] = 'Z'
		end

	append_padded_integer (a_target: STRING_8; a_value, a_width: INTEGER)
		local
			text: STRING_8
		do
			text := a_value.out
			from until text.count >= a_width loop
				text.prepend_character ('0')
			end
			a_target.append (text)
		end

feature {NONE} -- Redaction

	sanitized_object (a_object: JSON_OBJECT): JSON_OBJECT
		local
			l_key: JSON_STRING
		do
			create Result.make_with_capacity (a_object.count)
			across a_object as c loop
				create l_key.make_from_string_32 (c.key.unescaped_string_32)
				if is_secret_key (c.key.unescaped_string_32) then
					Result.put (redaction_value, l_key)
				else
					Result.put (sanitized_value (c.item), l_key)
				end
			end
		end

	sanitized_value (a_value: JSON_VALUE): JSON_VALUE
		local
			a: JSON_ARRAY
		do
			if attached {JSON_OBJECT} a_value as source_object then
				Result := sanitized_object (source_object)
			elseif attached {JSON_ARRAY} a_value as source_array then
				create a.make (source_array.count)
				across source_array as c loop
					a.extend (sanitized_value (c.item))
				end
				Result := a
			elseif attached {JSON_STRING} a_value as source_string then
				create {JSON_STRING} Result.make_from_string_32 (source_string.unescaped_string_32)
			elseif attached {JSON_NUMBER} a_value as source_number then
				if source_number.is_integer then
					create {JSON_NUMBER} Result.make_integer (source_number.integer_64_item)
				elseif source_number.is_natural then
					create {JSON_NUMBER} Result.make_natural (source_number.natural_64_item)
				else
					create {JSON_NUMBER} Result.make_real (source_number.real_64_item)
				end
			elseif attached {JSON_BOOLEAN} a_value as source_boolean then
				create {JSON_BOOLEAN} Result.make (source_boolean.item)
			else
				create {JSON_NULL} Result
			end
		end

	redaction_value: JSON_STRING
		do
			create Result.make_from_string ("[REDACTED]")
		end

feature {NONE} -- Sinks

	emit_line (a_line: READABLE_STRING_8)
			-- Serialize sink writes so every physical JSON line remains intact.
		local
			l_stdout_ok, l_fallback: BOOLEAN
		do
			write_lock.lock
			l_stdout_ok := write_stdout_safely (a_line)
			l_fallback := not l_stdout_ok
			if attached log_file_path then
				if not file_sink_failed then
					file_sink_failed := not append_file_safely (a_line)
				end
				l_fallback := l_fallback or file_sink_failed
			end
			if l_fallback then
				write_stderr_safely (a_line)
			end
			write_lock.unlock
		end

	append_file_safely (a_line: READABLE_STRING_8): BOOLEAN
			-- Append `a_line', returning False instead of propagating an I/O exception.
		local
			l_file: detachable PLAIN_TEXT_FILE
			l_retried: BOOLEAN
		do
			if not l_retried and attached log_file_path as p then
				create l_file.make_with_path (p)
				l_file.open_append
				l_file.put_string (a_line)
				l_file.flush
				l_file.close
				Result := True
			end
		rescue
			l_retried := True
			close_safely (l_file)
			retry
		end

	write_stdout_safely (a_line: READABLE_STRING_8): BOOLEAN
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				io.output.put_string (a_line)
				io.output.flush
				Result := True
			end
		rescue
			l_retried := True
			retry
		end

	write_stderr_safely (a_line: READABLE_STRING_8)
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				io.error.put_string (a_line)
				io.error.flush
			end
		rescue
			l_retried := True
			retry
		end

	close_safely (a_file: detachable FILE)
		local
			l_retried: BOOLEAN
		do
			if not l_retried and then attached a_file as f and then not f.is_closed then
				f.close
			end
		rescue
			l_retried := True
			retry
		end

feature {NONE} -- Implementation

	clock: SYM_CLOCK

	write_lock: MUTEX

	secret_keys: SYM_SECRET_KEYS once create Result end

	debug_level: STRING_8 = "debug"

	info_level: STRING_8 = "info"

	warning_level: STRING_8 = "warning"

	error_level: STRING_8 = "error"

invariant
	clock_attached: clock /= Void
	write_lock_attached: write_lock /= Void

end
