note
	description: "Thread-safe stdout/stderr accumulator for Eiffel process callbacks."

class
	SYM_PROCESS_OUTPUT

create
	make

feature {NONE} -- Initialization

	make
		do
			create mutex.make
			create output.make_empty
			create errors.make_empty
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
		rescue
			if locked then mutex.unlock end
			create Result.make_empty
		end

feature {NONE} -- Storage

	append_bounded (a_target: STRING_8; a_chunk: READABLE_STRING_8)
			-- Retain only a small diagnostic prefix. Hook output is never placed in
			-- propagated errors, but capture must still have a memory bound.
		local
			remaining: INTEGER
		do
			remaining := max_capture_bytes - a_target.count
			if remaining > 0 then
				if a_chunk.count <= remaining then
					a_target.append (a_chunk)
				else
					a_target.append (a_chunk.substring (1, remaining))
				end
			end
		end

	max_capture_bytes: INTEGER = 65_536

	mutex: MUTEX

	output: STRING_8

	errors: STRING_8

end
