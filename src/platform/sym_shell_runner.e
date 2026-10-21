note
	description: "Host-shell execution with cwd enforcement, output capture, and timeout."

class
	SYM_SHELL_RUNNER

create
	make,
	make_with_output_limit

feature {NONE} -- Initialization

	make
		do
			make_with_output_limit (65_536)
		ensure
			default_output_limit: output_limit = 65_536
		end

	make_with_output_limit (a_limit: INTEGER)
		require
			positive_limit: a_limit > 0
		do
			output_limit := a_limit.max (1)
			create last_result.make (False, False, -1, "", "")
		ensure
			limit_set: output_limit = a_limit.max (1)
			not_launched: not last_result.launched
			not_timed_out: not last_result.timed_out
			initial_exit_code: last_result.exit_code = -1
		end

feature -- Access

	last_result: SYM_PROCESS_RESULT

	output_limit: INTEGER
			-- Independent retained stdout/stderr byte limit for each run.

	last_output_truncated: BOOLEAN
			-- Was stdout or stderr truncated in the last run?

feature -- Execution

	run_hook (a_script: READABLE_STRING_GENERAL; a_cwd: PATH; a_timeout_ms: INTEGER_64)
			-- Run hook in the host-appropriate noninteractive shell.
		require
			positive_timeout: a_timeout_ms > 0
		local
			args: ARRAYED_LIST [READABLE_STRING_GENERAL]
		do
			create args.make (5)
			if {PLATFORM}.is_windows then
				args.extend ("-NoProfile")
				args.extend ("-NonInteractive")
				args.extend ("-ExecutionPolicy")
				args.extend ("Bypass")
				args.extend ("-Command")
				args.extend (a_script)
				run (powershell_executable, args, a_cwd, a_timeout_ms)
			else
				args.extend ("-lc")
				args.extend (a_script)
				run ("sh", args, a_cwd, a_timeout_ms)
			end
		ensure
			result_recorded: last_result /= old last_result
		end

	run_bash (a_command: READABLE_STRING_GENERAL; a_cwd: PATH; a_timeout_ms: INTEGER_64)
			-- Run the Codex launch command exactly through bash -lc.
		require
			command_present: not a_command.is_empty
			positive_timeout: a_timeout_ms > 0
		local
			args: ARRAYED_LIST [READABLE_STRING_GENERAL]
		do
			create args.make (2)
			args.extend ("-lc")
			args.extend (a_command)
			run (bash_executable, args, a_cwd, a_timeout_ms)
		ensure
			result_recorded: last_result /= old last_result
		end

	run (a_executable: READABLE_STRING_GENERAL; a_arguments: ITERABLE [READABLE_STRING_GENERAL]; a_cwd: PATH; a_timeout_ms: INTEGER_64)
		require
			executable_present: not a_executable.is_empty
			positive_timeout: a_timeout_ms > 0
		local
			factory: PROCESS_FACTORY
			process: PROCESS
			capture: SYM_PROCESS_OUTPUT
			timed_out, retried: BOOLEAN
			timeout: INTEGER
		do
			if not retried then
				last_output_truncated := False
				create factory
				process := factory.process_launcher (a_executable, a_arguments, a_cwd.name)
				process.set_hidden (True)
				process.set_separate_console (False)
				process.enable_launch_in_new_process_group
				create capture.make_with_limit (output_limit)
				process.redirect_output_to_agent (agent capture.append_output)
				process.redirect_error_to_agent (agent capture.append_error)
				process.launch
				if process.launched then
					timeout := a_timeout_ms.max (1).min ({INTEGER}.max_value).to_integer_32
					process.wait_for_exit_with_timeout (timeout)
					if not process.has_exited then
						timed_out := True
						process.terminate_tree
						process.wait_for_exit_with_timeout (5_000)
					end
					if process.has_exited then
						create last_result.make (True, timed_out, process.exit_code, capture.output_snapshot, capture.error_snapshot)
					else
						create last_result.make (True, True, -1, capture.output_snapshot, capture.error_snapshot)
					end
					last_output_truncated := capture.has_overflowed
				else
					create last_result.make (False, False, -1, "", "process launch failed")
				end
			end
		ensure
			result_recorded: last_result /= old last_result
		rescue
			if attached process as owned_process then terminate_after_exception (owned_process) end
			last_output_truncated := False
			create last_result.make (False, False, -1, "", "unexpected process launch failure")
			retried := True
			retry
		end

feature {NONE} -- Exceptional process cleanup

	terminate_after_exception (a_process: PROCESS)
			-- Attempt bounded cleanup even if launch/wait/capture raised.
		local
			retried: BOOLEAN
		do
			if not retried and then a_process.launched and then not a_process.has_exited then
				if not a_process.force_terminated then a_process.terminate_tree end
				a_process.wait_for_exit_with_timeout (5_000)
			end
		rescue
			-- Preserve the caller's generic error even if native cleanup raises.
			retried := True
			retry
		end

feature -- Shell selection

	bash_executable: STRING_32
		local
			f: RAW_FILE
		do
			if attached environment.item ("SYMPHONY_BASH") as configured and then not configured.is_empty then
				Result := configured
			elseif {PLATFORM}.is_windows then
				Result := "C:\Program Files\Git\bin\bash.exe"
				create f.make_with_name (Result)
				if not f.exists then Result := "bash.exe" end
			else
				Result := "bash"
			end
		ensure
			executable_present: not Result.is_empty
		end

	powershell_executable: STRING_32
		do
			if attached environment.item ("SystemRoot") as root then
				Result := root + "\System32\WindowsPowerShell\v1.0\powershell.exe"
			else
				Result := "powershell.exe"
			end
		ensure
			executable_present: not Result.is_empty
		end

feature {NONE} -- Shared environment

	environment: EXECUTION_ENVIRONMENT once create Result end

invariant
	positive_output_limit: output_limit > 0

end
