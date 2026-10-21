note
	description: "Queued process outcomes and invocation capture; never starts a real process."

class
	SYM_FAKE_SHELL_RUNNER

inherit
	SYM_SHELL_RUNNER
		redefine
			make,
			run
		end

create
	make

feature {NONE} -- Initialization

	make
		do
			Precursor
			create results.make (4)
			create truncations.make (4)
			create arguments.make (10)
			create executable.make_empty
			create cwd.make_empty
			create timeouts.make (4)
		end

feature -- Observation

	call_count: INTEGER

	executable: STRING_32

	arguments: ARRAYED_LIST [STRING_32]

	cwd: PATH

	timeouts: ARRAYED_LIST [INTEGER_64]

	pending_count: INTEGER
		do
			Result := results.count
		end

feature -- Queued outcomes

	enqueue (a_result: SYM_PROCESS_RESULT)
		do
			results.extend (a_result)
			truncations.extend (False)
		end

	enqueue_success (a_output: READABLE_STRING_8)
		do
			enqueue (create {SYM_PROCESS_RESULT}.make (True, False, 0, a_output, ""))
		end

	enqueue_truncated_success (a_output: READABLE_STRING_8)
			-- Retained bytes can look complete even though the stream was truncated.
		do
			enqueue_success (a_output)
			truncations.put_i_th (True, truncations.count)
		end

feature -- Execution

	run (a_executable: READABLE_STRING_GENERAL; a_arguments: ITERABLE [READABLE_STRING_GENERAL]; a_cwd: PATH; a_timeout_ms: INTEGER_64)
		do
			call_count := call_count + 1
			executable := a_executable.to_string_32.twin
			create arguments.make (10)
			across a_arguments as c loop arguments.extend (c.item.to_string_32.twin) end
			cwd := a_cwd
			timeouts.extend (a_timeout_ms)
			last_output_truncated := False
			if results.is_empty then
				create last_result.make (False, False, -1, "", "No queued fake process outcome")
			else
				last_result := results.first
				last_output_truncated := truncations.first
				results.start
				results.remove
				truncations.start
				truncations.remove
			end
		end

feature {NONE} -- Storage

	results: ARRAYED_LIST [SYM_PROCESS_RESULT]

	truncations: ARRAYED_LIST [BOOLEAN]

end
