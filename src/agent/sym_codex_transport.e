note
	description: "Bidirectional Codex app-server subprocess transport over JSONL stdio."

class
	SYM_CODEX_TRANSPORT

create
	make

feature {NONE} -- Initialization

	make
		do
			create inbox.make
			create json
		ensure
			not_running: not is_running
			no_live_processes: not has_live_processes
			no_process_id: process_id = Void
			no_error: last_error = Void
			no_message: last_message = Void
			no_diagnostics: diagnostics.is_empty
		end

feature -- Status

	is_running: BOOLEAN
		do
			Result := attached process as p and then p.is_running
		ensure
			running_process_available: Result implies attached process as p and then p.is_running
		end

	has_live_processes: BOOLEAN
			-- Does the launched process or its attached OS group still contain a process?
		do
			Result := (attached process_guard as guard and then guard.has_live_members) or else is_running
		ensure
			running_process_is_live: is_running implies Result
			no_owner_is_not_live: (process = Void and process_guard = Void) implies not Result
		end

	process_id: detachable STRING_32
		do
			if attached process as p and then p.launched then Result := p.id.out end
		ensure
			id_present: attached Result as id implies not id.is_empty
			id_requires_launched_process: Result /= Void implies
				attached process as p and then p.launched
		end

	last_error: detachable SYM_ERROR

	last_message: detachable JSON_OBJECT

	diagnostics: STRING_8
		do
			Result := inbox.diagnostic_snapshot
		ensure
			bounded: Result.count <= 65_536
		end

feature -- Lifecycle

	start (a_command: READABLE_STRING_GENERAL; a_cwd, a_workspace_root: PATH; a_secret_names: ITERABLE [STRING_32])
		require
			command_present: not a_command.is_empty
			no_live_processes: not has_live_processes
		local
			factory: PROCESS_FACTORY
			p: PROCESS
			guard: SYM_PROCESS_GROUP_GUARD
			args: ARRAYED_LIST [READABLE_STRING_GENERAL]
			command: STRING_32
		do
			last_error := Void
			last_message := Void
			containment_failed := False
			if not safety.is_existing_workspace_directory (a_workspace_root, a_cwd) then
				create last_error.make ("workspace_path_escape", "Codex cwd must be a per-issue workspace inside workspace.root")
			else
				command := unset_prefix (a_secret_names) + "exec " + a_command.to_string_32
				create args.make (2)
				args.extend ("-lc")
				args.extend (command)
				create factory
				p := factory.process_launcher (shell.bash_executable, args, a_cwd.canonical_path.name)
				p.set_hidden (True)
				p.set_separate_console (False)
				p.enable_launch_in_new_process_group
				p.set_buffer_size (65_536)
				p.redirect_input_to_stream
				p.redirect_output_to_agent (agent inbox.append_stdout)
				p.redirect_error_to_agent (agent inbox.append_stderr)
				p.set_environment_variable_table (filtered_environment (a_secret_names))
				-- Publish the launcher before `launch': if the process library raises after
				-- creating the child, runner cleanup still has the strongest handle available.
				process := p
				p.launch
				if p.launched then
					create guard.make (p.id)
					if guard.is_attached then
						process_guard := guard
					else
						containment_failed := True
						create last_error.make ("codex_launch_error",
							"Failed to establish OS process-group containment")
					end
				else
					create last_error.make ("codex_launch_error", "Failed to launch bash/Codex app-server")
				end
			end
		ensure
			contained_or_error: last_error /= Void or else
				(attached process_guard as attached_guard and then attached_guard.is_attached)
		rescue
			-- Preserve any launched process and guard so `stop' can still own and
			-- terminate them during runner cleanup.
			if process /= Void and then process_guard = Void then
				containment_failed := True
			end
			create last_error.make ("codex_launch_error", "Unexpected app-server process launch failure")
		end

	stop
		local
			started_at_ms: INTEGER_64
		do
			last_error := Void
			if attached process_guard as initial_guard then
				initial_guard.terminate
			end
			if attached process as p then
				if p.launched then
					if not p.has_exited then
						if not p.force_terminated then
							if process_guard /= Void then
								p.terminate_tree
							else
								-- Without a verified group, Unix `terminate_tree' may target a
								-- nonexistent negative PGID and then suppress later attempts.
								-- Startup failed before the protocol handshake, so terminate the
								-- directly owned root PID instead.
								p.terminate
							end
						end
						p.wait_for_exit_with_timeout (5_000)
					end
					if not p.has_exited then
						-- Retain ownership so the caller can keep the issue claimed and retry
						-- shutdown; dropping this handle could orphan a mutating child.
						create last_error.make ("codex_termination_error",
							"App-server did not exit after the termination timeout")
					end
				else
					process := Void
				end
			end
			if attached process_guard as remaining_guard then
				started_at_ms := clock.monotonic_milliseconds
				from until not remaining_guard.has_live_members or else
					clock.monotonic_milliseconds - started_at_ms >= 5_000
				loop
					environment.sleep (10_000_000)
				end
				if remaining_guard.has_live_members then
					create last_error.make ("codex_termination_error",
						"App-server process group did not exit after the termination timeout")
				else
					remaining_guard.close_when_empty
					process_guard := Void
				end
			end
			-- A containment-attachment failure already made startup fail before any
			-- protocol request was sent. Once the direct launcher is confirmed exited,
			-- do not keep the worker alive forever solely because no group handle exists.
			if last_error = Void then
				process := Void
				containment_failed := False
			end
		ensure
			terminated_or_error: last_error /= Void or else not has_live_processes
		rescue
			create last_error.make ("codex_termination_error",
				"Unexpected failure while terminating app-server")
		end

feature -- Messaging

	send (a_message: JSON_OBJECT)
		do
			last_error := Void
			if attached process as p and then p.is_running then
				p.put_string (a_message.representation + "%N")
				if p.has_input_error then create last_error.make ("codex_write_error", "Failed writing JSONL message to app-server") end
			else
				create last_error.make ("codex_process_exit", "App-server is not running")
			end
		ensure
			unavailable_process_reported: not (old is_running) implies last_error /= Void
		rescue
			create last_error.make ("codex_write_error", "Unexpected app-server stdin failure")
		end

	next_message (a_silence_timeout_ms: INTEGER_64)
			-- Wait for one valid JSON object. Noise is ignored; activity resets the silence timeout.
		require
			positive_timeout: a_silence_timeout_ms > 0
		do
			read_next_message (a_silence_timeout_ms, True)
		ensure
			message_or_error: (last_message /= Void) /= (last_error /= Void)
		end

	next_message_with_absolute_timeout (a_timeout_ms: INTEGER_64)
			-- Wait for one valid JSON object for at most `a_timeout_ms` in total.
			-- Stream noise and diagnostics do not extend this request deadline.
		require
			positive_timeout: a_timeout_ms > 0
		do
			read_next_message (a_timeout_ms, False)
		ensure
			message_or_error: (last_message /= Void) /= (last_error /= Void)
		end

feature {NONE} -- Message wait implementation

	read_next_message (a_timeout_ms: INTEGER_64; a_activity_extends_timeout: BOOLEAN)
		local
			line: detachable STRING_8
			started_at, deadline_base, now: INTEGER_64
			done: BOOLEAN
		do
			last_error := Void
			last_message := Void
			started_at := clock.monotonic_milliseconds
			deadline_base := inbox.activity_milliseconds
			from until done loop
				now := clock.monotonic_milliseconds
				if not a_activity_extends_timeout and then now - started_at >= a_timeout_ms then
					create last_error.make ("codex_timeout", "App-server response was not received before the configured timeout")
					done := True
				else
					line := inbox.next_line
					if attached line as l then
						if a_activity_extends_timeout then deadline_base := inbox.activity_milliseconds end
						if attached json.parsed_object (l) as m then
							last_message := m
							done := True
						elseif not l.is_empty and then l [1] = '{' then
							create last_error.make ("codex_malformed_message", "Malformed JSON object from app-server")
							done := True
						end
					elseif inbox.has_overflowed then
						create last_error.make ("codex_line_too_large", "App-server output exceeded the 10 MiB line limit")
						done := True
					elseif not is_running then
						create last_error.make ("codex_process_exit", "App-server exited while awaiting a message")
						done := True
					else
						if a_activity_extends_timeout and then inbox.activity_milliseconds > deadline_base then
							deadline_base := inbox.activity_milliseconds
						end
						if a_activity_extends_timeout and then now - deadline_base >= a_timeout_ms then
							create last_error.make ("codex_timeout", "App-server stream was silent past the configured timeout")
							done := True
						else
							environment.sleep (10_000_000)
						end
					end
				end
			end
		end

feature {NONE} -- Child environment

	filtered_environment (a_secret_names: ITERABLE [STRING_32]): HASH_TABLE [READABLE_STRING_GENERAL, READABLE_STRING_GENERAL]
		do
			create Result.make (environment.starting_environment.count + 1)
			across environment.starting_environment as c loop
				if not contains_caseless (a_secret_names, c.key) then Result.force (c.item, c.key) end
			end
			Result.force ("1", "SYMPHONY_CHILD")
		end

	unset_prefix (a_secret_names: ITERABLE [STRING_32]): STRING_32
		do
			create Result.make_empty
			across a_secret_names as c loop
				if is_shell_variable_name (c.item) then
					Result.append_string_general ("unset ")
					Result.append (c.item)
					Result.append_string_general ("; ")
				end
			end
		end

	contains_caseless (a_names: ITERABLE [STRING_32]; a_name: READABLE_STRING_GENERAL): BOOLEAN
		do
			across a_names as c until Result loop Result := c.item.is_case_insensitive_equal_general (a_name) end
		end

	is_shell_variable_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
		local
			i: INTEGER
			c: CHARACTER_32
		do
			Result := not a_name.is_empty
			from i := 1 until i > a_name.count or not Result loop
				c := a_name [i]
				if i = 1 then
					Result := (c >= 'A' and c <= 'Z') or else (c >= 'a' and c <= 'z') or else c = '_'
				else
					Result := (c >= 'A' and c <= 'Z') or else (c >= 'a' and c <= 'z') or else (c >= '0' and c <= '9') or else c = '_'
				end
				i := i + 1
			end
		end

feature {NONE} -- Collaborators

	process: detachable PROCESS

	process_guard: detachable SYM_PROCESS_GROUP_GUARD

	containment_failed: BOOLEAN

	inbox: SYM_JSONL_INBOX

	json: SYM_JSON

	safety: SYM_PATH_SAFETY once create Result end

	shell: SYM_SHELL_RUNNER once create Result.make end

	clock: SYM_CLOCK once create Result end

	environment: EXECUTION_ENVIRONMENT once create Result end

end
