note
	description: "UTC wall-clock values used for logs, retries, and session metrics."

class
	SYM_CLOCK

feature -- Time

	now_utc: DATE_TIME
		do
			create Result.make_now_utc
		end

	now_epoch_milliseconds: INTEGER_64
		local
			n: DATE_TIME
			d: DATE_TIME_DURATION
		do
			create n.make_now_utc
			d := n.relative_duration (unix_epoch)
			Result := (d.fine_seconds_count * 1000.0).truncated_to_integer_64
		end

	monotonic_milliseconds: INTEGER_64
			-- Milliseconds from an arbitrary process-independent monotonic origin.
		external
			"C inline use <sym_monotonic.h>"
		alias
			"return (EIF_INTEGER_64) sym_monotonic_milliseconds();"
		end

	iso_8601_now: STRING_8
		do
			Result := iso_8601 (now_utc)
		end

	iso_8601 (a_time: DATE_TIME): STRING_8
		local
			l_ms: INTEGER
		do
			l_ms := ((a_time.fine_second - a_time.second) * 1000.0).truncated_to_integer.max (0).min (999)
			create Result.make (24)
			append_padded_integer (Result, a_time.year, 4)
			Result.append_character ('-')
			append_padded_integer (Result, a_time.month, 2)
			Result.append_character ('-')
			append_padded_integer (Result, a_time.day, 2)
			Result.append_character ('T')
			append_padded_integer (Result, a_time.hour, 2)
			Result.append_character (':')
			append_padded_integer (Result, a_time.minute, 2)
			Result.append_character (':')
			append_padded_integer (Result, a_time.second, 2)
			Result.append_character ('.')
			append_padded_integer (Result, l_ms, 3)
			Result.append_character ('Z')
		ensure
			rfc3339_shape: Result.count = 24 and then Result [11] = 'T' and then Result [24] = 'Z'
		end

feature {NONE} -- Implementation

	unix_epoch: DATE_TIME
		once
			create Result.make (1970, 1, 1, 0, 0, 0)
		end

	three_digits (a_value: INTEGER): STRING_8
		do
			Result := a_value.max (0).min (999).out
			from until Result.count >= 3 loop
				Result.prepend_character ('0')
			end
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

end
