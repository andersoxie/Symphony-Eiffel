note
	description: "Thread-safe partial-line buffer for Codex JSONL stdout and diagnostic stderr."

class
	SYM_JSONL_INBOX

create
	make

feature {NONE} -- Initialization

	make
		do
			create mutex.make
			create partial.make_empty
			create lines.make (20)
			create diagnostics.make_empty
			last_activity_ms := clock.monotonic_milliseconds
		ensure
			no_pending_lines: lines.is_empty and partial.is_empty
			no_diagnostics: diagnostic_snapshot.is_empty
			not_overflowed: not has_overflowed
			activity_initialized: last_activity_ms >= 0
		end

feature -- Callback input

	append_stdout (a_chunk: READABLE_STRING_8)
		local
			i: INTEGER
			line: STRING_8
		do
			mutex.lock
			last_activity_ms := clock.monotonic_milliseconds
			if not overflowed then
				partial.append (a_chunk)
				from i := partial.index_of ('%N', 1) until i = 0 or overflowed loop
					line := partial.substring (1, i - 1)
					if line.ends_with ("%R") then line.remove_tail (1) end
					if line.count > max_line_size then
						overflowed := True
						lines.wipe_out
						partial.wipe_out
					else
						lines.extend (line)
						partial.remove_head (i)
						i := partial.index_of ('%N', 1)
					end
				end
				if not overflowed and then partial.count > max_line_size then
					overflowed := True
					lines.wipe_out
					partial.wipe_out
				end
			end
			mutex.unlock
		ensure
			partial_line_bounded: partial.count <= max_line_size
			overflow_clears_pending_input: overflowed implies partial.is_empty and lines.is_empty
		rescue
			mutex.unlock
		end

	append_stderr (a_chunk: READABLE_STRING_8)
		do
			mutex.lock
			last_activity_ms := clock.monotonic_milliseconds
			diagnostics.append (a_chunk)
			if diagnostics.count > max_diagnostic_size then diagnostics.remove_head (diagnostics.count - max_diagnostic_size) end
			mutex.unlock
		ensure
			diagnostics_bounded: diagnostics.count <= max_diagnostic_size
		rescue
			mutex.unlock
		end

feature -- Consumption

	next_line: detachable STRING_8
		do
			mutex.lock
			if not lines.is_empty then
				lines.start
				Result := lines.item
				lines.remove
			end
			mutex.unlock
		ensure
			line_size_bounded: attached Result as line implies line.count <= max_line_size
			line_terminator_removed: attached Result as line implies not line.ends_with ("%R")
		rescue
			mutex.unlock
			Result := Void
		end

	activity_milliseconds: INTEGER_64
		do
			mutex.lock
			Result := last_activity_ms
			mutex.unlock
		ensure
			non_negative: Result >= 0
		rescue
			mutex.unlock
		end

	diagnostic_snapshot: STRING_8
		do
			mutex.lock
			Result := diagnostics.twin
			mutex.unlock
		ensure
			bounded: Result.count <= max_diagnostic_size
			independent_copy: Result /= diagnostics
		rescue
			mutex.unlock
			create Result.make_empty
		end

	has_overflowed: BOOLEAN
		do
			mutex.lock
			Result := overflowed
			mutex.unlock
		ensure
			overflow_clears_pending_input: Result implies partial.is_empty and lines.is_empty
		rescue
			mutex.unlock
		end

feature {NONE} -- Storage

	mutex: MUTEX

	partial: STRING_8

	lines: ARRAYED_LIST [STRING_8]

	diagnostics: STRING_8

	last_activity_ms: INTEGER_64

	overflowed: BOOLEAN

	max_line_size: INTEGER = 10_485_760

	max_diagnostic_size: INTEGER = 65_536

	clock: SYM_CLOCK once create Result end

end
