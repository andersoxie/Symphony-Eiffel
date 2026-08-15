note
	description: "Safe deterministic workspace lifecycle and hooks."

class
	SYM_WORKSPACE_MANAGER

create
	make

feature {NONE} -- Initialization

	make
		do
			create shell.make
		end

feature -- Result

	workspace: detachable SYM_WORKSPACE

	error: detachable SYM_ERROR

	warning: detachable SYM_ERROR
			-- Most recent best-effort hook failure, if any.

	is_success: BOOLEAN
		do
			Result := workspace /= Void and error = Void
		end

	set_event_handler (a_handler: detachable PROCEDURE [SYM_AGENT_EVENT])
		do
			event_handler := a_handler
		end

feature -- Lifecycle

	create_for_issue (a_identifier: READABLE_STRING_GENERAL; a_config: SYM_CONFIG)
		local
			root_dir, issue_dir: DIRECTORY
			p: detachable PATH
			created_now: BOOLEAN
			key: STRING_32
			f: RAW_FILE
		 do
			workspace := Void
			error := Void
			warning := Void
			create root_dir.make_with_path (a_config.workspace_root)
			if not root_dir.exists then root_dir.recursive_create_dir end
			if not root_dir.exists then
				set_error ("workspace_error", "Could not create workspace root")
			else
				key := safety.workspace_key (a_identifier)
				p := safety.workspace_path (a_config.workspace_root, a_identifier)
				if not attached p as path then
					set_error ("workspace_path_escape", "Derived workspace is outside workspace.root")
				else
					create f.make_with_path (path)
					create issue_dir.make_with_path (path)
					if f.path_exists and then f.is_symlink then
						set_error ("workspace_path_escape", "Workspace path is a symbolic link or reparse point")
					elseif f.exists and then not issue_dir.exists then
						set_error ("workspace_collision", "Workspace path exists and is not a directory")
					else
						if not issue_dir.exists then
							issue_dir.create_dir
							created_now := issue_dir.exists
						end
						if issue_dir.exists and then not created_now and then has_incomplete_marker (path) then
							if safety.is_existing_workspace_directory (a_config.workspace_root, path) then
								issue_dir.recursive_delete
								if not issue_dir.exists then
									issue_dir.create_dir
									created_now := issue_dir.exists
								else
									set_error ("workspace_remove_error", "Could not reset an incomplete workspace")
								end
							else
								set_error ("workspace_path_escape", "Incomplete workspace is not a safe directory under workspace.root")
							end
						end
						if not issue_dir.exists then
							set_error ("workspace_error", "Could not create per-issue workspace")
						elseif not safety.is_existing_workspace_directory (a_config.workspace_root, path) then
							set_error ("workspace_path_escape", "Workspace containment check failed")
						elseif created_now and attached a_config.after_create_hook as hook and then not strings.is_blank (hook) then
							if not mark_incomplete (path) then
								set_error ("workspace_error", "Could not mark the new workspace as incomplete")
								if safety.is_existing_workspace_directory (a_config.workspace_root, path) then issue_dir.recursive_delete end
							else
								emit_hook_event ("after_create", "started", Void)
								shell.run_hook (hook, path, a_config.hook_timeout_ms)
								if shell.last_result.is_success and then safety.is_existing_workspace_directory (a_config.workspace_root, path) then
									if clear_incomplete (path) then
										create workspace.make (path, key, True)
										emit_hook_event ("after_create", "completed", Void)
									else
										set_error ("workspace_error", "Could not finalize the newly initialized workspace")
									end
								else
									if shell.last_result.is_success then
										set_error ("workspace_path_escape", "after_create replaced the workspace with a symbolic link or moved it outside the root")
									else
										set_hook_error ("after_create", shell.last_result)
									end
									if attached error as hook_error then emit_hook_event ("after_create", "failed", hook_error) end
								end
								if workspace = Void then
									-- Keep the marker on failed deletion so no later attempt can silently
									-- reuse a partially initialized workspace.
									if safety.is_existing_workspace_directory (a_config.workspace_root, path) then
										issue_dir.recursive_delete
									end
								end
							end
						else
							create workspace.make (path, key, created_now)
						end
					end
				end
			end
		rescue
			workspace := Void
			set_error ("workspace_error", "Unexpected workspace creation failure")
		end

	run_before_run (a_workspace: SYM_WORKSPACE; a_config: SYM_CONFIG): BOOLEAN
		do
			error := Void
			warning := Void
			Result := True
			if not safety.is_existing_workspace_directory (a_config.workspace_root, a_workspace.path) then
				Result := False
				set_error ("workspace_path_escape", "Workspace became a symbolic link or moved outside the configured root")
			elseif attached a_config.before_run_hook as hook and then not strings.is_blank (hook) then
				emit_hook_event ("before_run", "started", Void)
				shell.run_hook (hook, a_workspace.path, a_config.hook_timeout_ms)
				Result := shell.last_result.is_success and then safety.is_existing_workspace_directory (a_config.workspace_root, a_workspace.path)
				if not shell.last_result.is_success then
					set_hook_error ("before_run", shell.last_result)
				elseif not Result then
					set_error ("workspace_path_escape", "before_run replaced the workspace with a symbolic link or moved it outside the root")
				end
				if attached error as hook_error then emit_hook_event ("before_run", "failed", hook_error) else emit_hook_event ("before_run", "completed", Void) end
			end
		end

	run_after_run (a_workspace: SYM_WORKSPACE; a_config: SYM_CONFIG)
			-- Best effort by contract.
		do
			warning := Void
			if attached a_config.after_run_hook as hook and then not strings.is_blank (hook) then
				if safety.is_existing_workspace_directory (a_config.workspace_root, a_workspace.path) then
					emit_hook_event ("after_run", "started", Void)
					shell.run_hook (hook, a_workspace.path, a_config.hook_timeout_ms)
					if not shell.last_result.is_success then
						set_hook_warning ("after_run", shell.last_result)
						emit_hook_event ("after_run", "failed", warning)
					else
						emit_hook_event ("after_run", "completed", Void)
					end
				else
					create warning.make ("workspace_path_escape", "Skipping after_run because the workspace is no longer a safe directory under the configured root")
					emit_hook_event ("after_run", "failed", warning)
				end
			end
		end

	remove_for_issue (a_identifier: READABLE_STRING_GENERAL; a_config: SYM_CONFIG)
		local
			p: detachable PATH
			d: DIRECTORY
		do
			error := Void
			warning := Void
			p := safety.workspace_path (a_config.workspace_root, a_identifier)
			if attached p as path then
				create d.make_with_path (path)
				if d.exists then
					if not safety.is_existing_workspace_directory (a_config.workspace_root, path) then
						set_error ("workspace_path_escape", "Refusing to remove a symbolic-link/reparse-point workspace or a path outside workspace.root")
					else
						if attached a_config.before_remove_hook as hook and then not strings.is_blank (hook) then
							emit_hook_event ("before_remove", "started", Void)
							shell.run_hook (hook, path, a_config.hook_timeout_ms)
							if not shell.last_result.is_success then
								set_hook_warning ("before_remove", shell.last_result)
								emit_hook_event ("before_remove", "failed", warning)
							else
								emit_hook_event ("before_remove", "completed", Void)
							end
						end
						-- A trusted hook may still accidentally replace its cwd. Re-check before deletion.
						if safety.is_existing_workspace_directory (a_config.workspace_root, path) then
							d.recursive_delete
							if d.exists then set_error ("workspace_remove_error", "Workspace still exists after recursive deletion") end
						else
							set_error ("workspace_path_escape", "Refusing cleanup because before_remove changed the workspace path")
						end
					end
				end
			else
				set_error ("workspace_path_escape", "Refusing to remove path outside workspace.root")
			end
		rescue
			set_error ("workspace_remove_error", "Unexpected workspace cleanup failure")
		end

feature {NONE} -- Errors

	incomplete_marker (a_path: PATH): PATH
		do
			Result := a_path.extended (".symphony-incomplete")
		end

	has_incomplete_marker (a_path: PATH): BOOLEAN
		local
			file: RAW_FILE
		do
			create file.make_with_path (incomplete_marker (a_path))
			Result := file.exists
		rescue
			Result := True
		end

	mark_incomplete (a_path: PATH): BOOLEAN
		local
			file: PLAIN_TEXT_FILE
			retried: BOOLEAN
		do
			if not retried then
				create file.make_with_path (incomplete_marker (a_path))
				file.open_write
				file.put_string ("Workspace initialization has not completed.%N")
				file.close
				Result := True
			end
		rescue
			if attached file as open_file and then not open_file.is_closed then open_file.close end
			retried := True
			retry
		end

	clear_incomplete (a_path: PATH): BOOLEAN
		local
			file: RAW_FILE
			retried: BOOLEAN
		do
			if not retried then
				create file.make_with_path (incomplete_marker (a_path))
				if file.exists then file.delete end
				Result := not file.exists
			end
		rescue
			retried := True
			retry
		end

	set_hook_error (a_name: READABLE_STRING_GENERAL; a_result: SYM_PROCESS_RESULT)
		local
			message: STRING_32
		do
			message := a_name.to_string_32 + " hook failed"
			if a_result.timed_out then message.append_string_general (" (timeout)") else message.append_string_general (" exit_code=" + a_result.exit_code.out) end
			set_error ("workspace_hook_error", message)
		end

	set_hook_warning (a_name: READABLE_STRING_GENERAL; a_result: SYM_PROCESS_RESULT)
		local
			message: STRING_32
		do
			message := a_name.to_string_32 + " hook failed"
			if a_result.timed_out then message.append_string_general (" (timeout)") else message.append_string_general (" exit_code=" + a_result.exit_code.out) end
			create warning.make ("workspace_hook_error", message)
		end

	emit_hook_event (a_name, a_status: READABLE_STRING_GENERAL; a_error: detachable SYM_ERROR)
		local
			event: SYM_AGENT_EVENT
			message: STRING_32
		do
			message := "hook=" + a_name.to_string_32 + " status=" + a_status.to_string_32
			if attached a_error as value then message.append_string_general (" reason=" + value.code) end
			if attached event_handler as handler then
				if a_status.same_string ("failed") then
					create event.make ("workspace_hook_failed", Void, message)
				else
					create event.make ("workspace_hook_" + a_status.to_string_32, Void, message)
				end
				handler.call ([event])
			end
		end

	set_error (a_code, a_message: READABLE_STRING_GENERAL)
		do
			if error = Void then create error.make (a_code, a_message) end
		end

	shell: SYM_SHELL_RUNNER

	event_handler: detachable PROCEDURE [SYM_AGENT_EVENT]

	safety: SYM_PATH_SAFETY once create Result end

	strings: SYM_STRINGS once create Result end

end
