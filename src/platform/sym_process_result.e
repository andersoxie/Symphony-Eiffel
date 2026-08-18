note
	description: "Captured shell-process outcome."

class
	SYM_PROCESS_RESULT

create
	make

feature {NONE} -- Initialization

	make (a_launched, a_timed_out: BOOLEAN; a_exit_code: INTEGER; a_output, a_error: READABLE_STRING_8)
		require
			timeout_requires_launch: a_timed_out implies a_launched
		do
			launched := a_launched
			timed_out := a_timed_out
			exit_code := a_exit_code
			output := a_output.to_string_8
			error_output := a_error.to_string_8
		ensure
			launch_status_set: launched = a_launched
			timeout_status_set: timed_out = a_timed_out
			exit_code_set: exit_code = a_exit_code
			output_copied: output.same_string (a_output)
			error_output_copied: error_output.same_string (a_error)
		end

feature -- Access

	launched: BOOLEAN

	timed_out: BOOLEAN

	exit_code: INTEGER

	output: STRING_8

	error_output: STRING_8

	is_success: BOOLEAN
		do
			Result := launched and not timed_out and exit_code = 0
		ensure
			success_definition: Result = (launched and not timed_out and exit_code = 0)
		end

end
