note
	description: "Thread-safe stdout/stderr accumulator for Eiffel process callbacks."

class
	SYM_PROCESS_OUTPUT

create
	make,
	make_with_limit

feature {NONE} -- Initialization

	make
		do
			make_with_limit (65_536)
		ensure
			default_limit: max_capture_bytes = 65_536
		end

	make_with_limit (a_limit: INTEGER)
		require
			positive_limit: a_limit > 0
		do
			max_capture_bytes := a_limit.max (1)
			create mutex.make
			create output.make_empty
			create errors.make_empty
		ensure
			limit_set: max_capture_bytes = a_limit.max (1)
			output_empty: output_snapshot.is_empty
			error_empty: error_snapshot.is_empty
			no_overflow: not has_overflowed
		end

feature -- Access

	max_capture_bytes: INTEGER
			-- Independent byte limit for stdout and stderr.

	has_overflowed: BOOLEAN
			-- Has either stream exceeded its retained byte limit?
		local
			locked: BOOLEAN
		do
			mutex.lock
			locked := True
			Result := overflowed
			mutex.unlock
			locked := False
		rescue
			if locked then mutex.unlock end
		end

feature -- Callbacks

	append_output (a_chunk: READABLE_STRING_8)
		local
			locked: BOOLEAN
		do
			mutex.lock
			locked := True
			append_bounded (output, a_chunk)
			mutex.unlock
			locked := False
		ensure
			output_bounded: output.count <= max_capture_bytes
		rescue
			if locked then mutex.unlock end
		end

	append_error (a_chunk: READABLE_STRING_8)
		local
			locked: BOOLEAN
		do
			mutex.lock
			locked := True
			append_bounded (errors, a_chunk)
			mutex.unlock
			locked := False
		ensure
			error_bounded: errors.count <= max_capture_bytes
		rescue
			if locked then mutex.unlock end
		end

feature -- Snapshots

	output_snapshot: STRING_8
		local
			locked: BOOLEAN
		do
			mutex.lock
			locked := True
			Result := output.twin
			mutex.unlock
			locked := False
		ensure
			bounded: Result.count <= max_capture_bytes
			independent_copy: Result /= output
		rescue
			if locked then mutex.unlock end
			create Result.make_empty
		end

	error_snapshot: STRING_8
		local
			locked: BOOLEAN
		do
			mutex.lock
			locked := True
			Result := errors.twin
			mutex.unlock
			locked := False
		ensure
			bounded: Result.count <= max_capture_bytes
			independent_copy: Result /= errors
		rescue
			if locked then mutex.unlock end
			create Result.make_empty
		end

feature {NONE} -- Storage

	append_bounded (a_target: STRING_8; a_chunk: READABLE_STRING_8)
			-- Retain a bounded prefix and record any discarded bytes.
		local
			remaining: INTEGER
		do
			remaining := max_capture_bytes - a_target.count
			if a_chunk.count > remaining then overflowed := True end
			if remaining > 0 then
				if a_chunk.count <= remaining then
					a_target.append (a_chunk)
				else
					a_target.append (a_chunk.substring (1, remaining))
				end
			end
		end

	overflowed: BOOLEAN

	mutex: MUTEX

	output: STRING_8

	errors: STRING_8

invariant
	positive_limit: max_capture_bytes > 0
	output_bounded: output.count <= max_capture_bytes
	error_bounded: errors.count <= max_capture_bytes

end
