note
	description: "Synchronous workspace, prompt, app-server, and tracker-refresh execution for one issue."

class
	SYM_AGENT_RUNNER

create
	make

feature {NONE} -- Initialization

	make
		do
			create workspace_manager.make
			create prompt_renderer.make
			create last_session_id.make_empty
			create control_lock.make
			create client_stop_lock.make
		ensure
			no_outcome: outcome = Void
			no_client: client = Void
			not_running: not is_running
			cancellation_not_requested: not cancel_requested
		end

feature -- Result

	outcome: detachable SYM_WORKER_OUTCOME
			-- Outcome of the most recent `run'.

	client: detachable SYM_APP_SERVER_CLIENT
			-- Client for the current or most recent run; stopped before `run' returns.

	is_running: BOOLEAN

feature -- Events and cancellation

	set_event_handler (a_handler: detachable PROCEDURE [SYM_AGENT_EVENT])
			-- Forward app-server events to `a_handler'.
		local
			active_client: detachable SYM_APP_SERVER_CLIENT
			locked, retried: BOOLEAN
		do
			if not retried then
				control_lock.lock
				locked := True
				event_handler := a_handler
				active_client := client
				control_lock.unlock
				locked := False
				workspace_manager.set_event_handler (a_handler)
				if attached active_client as current_client then
					current_client.set_event_handler (a_handler)
				end
			end
		ensure
			handler_set_or_preserved: event_handler = a_handler or else event_handler = old event_handler
		rescue
			if locked then control_lock.unlock end
			retried := True
			retry
		end

	cancel
			-- Request cancellation and stop the active app-server process.
		local
			active_client: detachable SYM_APP_SERVER_CLIENT
			locked, retried: BOOLEAN
		do
			if not retried then
				control_lock.lock
				locked := True
				cancel_requested := True
				active_client := client
				control_lock.unlock
				locked := False
				if attached active_client as current_client then
					remember_session (current_client)
					stop_client_safely (current_client)
				end
			end
		ensure
			cancellation_is_sticky: old cancel_requested implies cancel_requested
		rescue
			if locked then control_lock.unlock end
			retried := True
			retry
		end

feature -- Execution

	run (
		a_issue: SYM_ISSUE;
		a_attempt: detachable INTEGER_64_REF;
		a_workflow: SYM_WORKFLOW;
		a_config: SYM_CONFIG;
		a_tracker: SYM_TRACKER_GATEWAY
	)
			-- Execute one worker attempt synchronously.
		require
			idle: not is_running
			positive_attempt: attached a_attempt as attempt implies attempt.item > 0
		local
			workspace: detachable SYM_WORKSPACE
			new_client: SYM_APP_SERVER_CLIENT
			failure: SYM_ERROR
			cleaned, retried: BOOLEAN
			do
			if not retried then
				outcome := Void
				begin_run
				if is_cancellation_requested then
					set_cancelled (a_issue)
				elseif not a_issue.is_core_valid then
					create failure.make ("invalid_issue", "Issue is missing a required core field")
					set_failure (failure, False, False, a_issue)
				elseif not a_config.is_valid then
					if attached a_config.error as config_error then
						set_failure (config_error, False, False, a_issue)
					else
						create failure.make ("invalid_config", "Cannot run an issue with invalid configuration")
						set_failure (failure, False, False, a_issue)
					end
				else
					workspace_manager.create_for_issue (a_issue.identifier, a_config)
					workspace := workspace_manager.workspace
					if attached workspace as prepared_workspace then
						if is_cancellation_requested then
							set_cancelled (a_issue)
						elseif not workspace_manager.run_before_run (prepared_workspace, a_config) then
							if attached workspace_manager.error as hook_error then
								set_failure (hook_error, True, False, a_issue)
							else
								create failure.make ("workspace_hook_error", "before_run hook failed")
								set_failure (failure, True, False, a_issue)
							end
						elseif is_cancellation_requested then
							set_cancelled (a_issue)
						else
							-- Rendering is part of attempt preparation. A strict template
							-- failure must not launch an app-server subprocess.
							prompt_renderer.render (a_workflow.prompt_template, a_issue, a_attempt)
							if attached prompt_renderer.error as prompt_error then
								set_failure (prompt_error, True, False, a_issue)
							elseif not prompt_renderer.is_success then
								create failure.make ("template_render_error", "Prompt rendering failed")
								set_failure (failure, True, False, a_issue)
							else
								create new_client.make
								publish_client (new_client)
								new_client.set_event_handler (current_event_handler)
								if is_cancellation_requested then
									set_cancelled (a_issue)
								else
									new_client.start_session (prepared_workspace, a_config,
										a_tracker.secret_environment_names)
									if attached new_client.last_error as startup_error then
										set_client_failure (startup_error, a_issue)
									elseif is_cancellation_requested then
										set_cancelled (a_issue)
									else
										outcome := execute_turns (prompt_renderer.rendered_prompt, a_issue, prepared_workspace, a_config, a_tracker, new_client)
									end
								end
							end
						end
						finish_attempt (prepared_workspace, a_issue.identifier, a_config)
						cleaned := True
					else
						if attached workspace_manager.error as workspace_error then
							set_failure (workspace_error, True, False, a_issue)
						else
							create failure.make ("workspace_error", "Workspace preparation returned no workspace")
							set_failure (failure, True, False, a_issue)
						end
					end
				end
				set_running (False)
			end
		ensure
			not_running: not is_running
			outcome_available: outcome /= Void
			client_stopped: attached client as last_client implies not last_client.has_live_process
		rescue
			retried := True
			if outcome = Void then
				create failure.make ("agent_runner_error", "Unexpected per-issue runner failure")
				set_failure (failure, True, False, a_issue)
			end
			if not cleaned and then attached workspace as prepared_workspace then
				finish_attempt (prepared_workspace, a_issue.identifier, a_config)
				cleaned := True
			elseif attached active_client_snapshot as active_client then
				remember_session (active_client)
				stop_client_safely (active_client)
			end
			set_running (False)
			retry
		end

feature {NONE} -- Turn loop

	execute_turns (
		a_initial_prompt: READABLE_STRING_GENERAL;
		a_issue: SYM_ISSUE;
		a_workspace: SYM_WORKSPACE;
		a_config: SYM_CONFIG;
		a_tracker: SYM_TRACKER_GATEWAY;
		a_client: SYM_APP_SERVER_CLIENT
	): SYM_WORKER_OUTCOME
		local
			current_issue: SYM_ISSUE
			prompt: STRING_32
			ids: ARRAYED_LIST [STRING_32]
			refresh: SYM_TRACKER_RESULT
			refreshed_issue: detachable SYM_ISSUE
			failure: SYM_ERROR
			turn_number: INTEGER
		do
			current_issue := a_issue
			prompt := a_initial_prompt.to_string_32
			turn_number := 1
			create ids.make (1)
			ids.extend (a_issue.id)
			from
			until
				Result /= Void
			loop
				if is_cancellation_requested then
					create failure.make ("agent_cancelled", "Agent run was cancelled")
					create Result.make_failure (failure, False, False,
						session_id_for (a_client), a_client.turn_count, current_issue)
				else
					a_client.run_turn (prompt, current_issue, a_workspace, a_config)
					remember_session (a_client)
					if is_cancellation_requested then
						create failure.make ("agent_cancelled", "Agent run was cancelled")
						create Result.make_failure (failure, False, False,
							session_id_for (a_client), a_client.turn_count, current_issue)
					elseif attached a_client.last_error as turn_error then
						create Result.make_failure (turn_error, is_retryable_client_error (turn_error), False,
							session_id_for (a_client), a_client.turn_count, current_issue)
					else
						refresh := a_tracker.fetch_issues_by_ids (ids)
						if attached refresh.error as tracker_error then
							create failure.make ("issue_state_refresh_failed",
								tracker_error.code + ": " + tracker_error.message)
							create Result.make_failure (failure, True, False,
								session_id_for (a_client), a_client.turn_count, current_issue)
						else
							refreshed_issue := issue_by_id (refresh.issues, a_issue.id)
							if not attached refreshed_issue as latest then
								create Result.make_success ("Issue was not returned by the tracker refresh",
									session_id_for (a_client), a_client.turn_count, Void)
							elseif a_config.is_terminal_state (latest.state) then
								create Result.make_terminal ("Issue reached a terminal state",
									session_id_for (a_client), a_client.turn_count, latest)
							elseif not a_config.is_active_state (latest.state) then
								create Result.make_success ("Issue is no longer in an active state",
									session_id_for (a_client), a_client.turn_count, latest)
							elseif not is_routable (latest, a_config) then
								create Result.make_success (routability_message (latest, a_config),
									session_id_for (a_client), a_client.turn_count, latest)
							elseif turn_number >= a_config.max_turns then
								create Result.make_success ("Maximum turns reached while the issue remains active",
									session_id_for (a_client), a_client.turn_count, latest)
							else
								current_issue := latest
								turn_number := turn_number + 1
								prompt := continuation_prompt (turn_number, a_config.max_turns)
							end
						end
					end
				end
			end
		ensure
			turn_limit_observed: Result.turn_count <= a_config.max_turns
		end

	issue_by_id (a_issues: ITERABLE [SYM_ISSUE]; a_id: READABLE_STRING_GENERAL): detachable SYM_ISSUE
		do
			across a_issues as cursor until Result /= Void loop
				if cursor.item.id.same_string_general (a_id) then
					Result := cursor.item
				end
			end
		end

	is_routable (a_issue: SYM_ISSUE; a_config: SYM_CONFIG): BOOLEAN
		do
			Result := a_issue.dispatchable and then
				strings.has_all_labels (a_issue.labels, a_config.required_labels)
		end

	routability_message (a_issue: SYM_ISSUE; a_config: SYM_CONFIG): STRING_32
			-- Include non-secret routing inputs so configuration mismatches are diagnosable.
		do
			create Result.make_from_string ("Issue is active but no longer routable (dispatchable=")
			Result.append_string_general (a_issue.dispatchable.out)
			Result.append_string_general (", labels=")
			Result.append_string_general (json.string_array (a_issue.labels).representation)
			Result.append_string_general (", required_labels=")
			Result.append_string_general (json.string_array (a_config.required_labels).representation)
			Result.append_character (')')
		end

	continuation_prompt (a_turn_number, a_max_turns: INTEGER): STRING_32
		do
			create Result.make (600)
			Result.append_string_general ("Continuation guidance:%N%N")
			Result.append_string_general ("- The previous Codex turn completed normally, but the tracker work item is still in an active state.%N")
			Result.append_string_general ("- This is continuation turn #")
			Result.append_integer (a_turn_number)
			Result.append_string_general (" of ")
			Result.append_integer (a_max_turns)
			Result.append_string_general (" for the current agent run.%N")
			Result.append_string_general ("- Resume from the current workspace and workpad state instead of restarting from scratch.%N")
			Result.append_string_general ("- The original task instructions and prior turn context are already present in this thread, so do not restate them before acting.%N")
			Result.append_string_general ("- Focus on the remaining ticket work and do not end the turn while the issue stays active unless you are truly blocked.%N")
		end

feature {NONE} -- Outcome construction

	set_failure (a_error: SYM_ERROR; a_should_retry, a_is_terminal: BOOLEAN;
		a_latest_issue: detachable SYM_ISSUE)
		do
			create outcome.make_failure (a_error, a_should_retry, a_is_terminal,
				current_session_id, current_turn_count, a_latest_issue)
		end

	set_client_failure (a_error: SYM_ERROR; a_latest_issue: detachable SYM_ISSUE)
		do
			set_failure (a_error, is_retryable_client_error (a_error), False, a_latest_issue)
		end

	set_cancelled (a_latest_issue: detachable SYM_ISSUE)
		local
			failure: SYM_ERROR
		do
			create failure.make ("agent_cancelled", "Agent run was cancelled")
			set_failure (failure, False, False, a_latest_issue)
		end

	is_retryable_client_error (a_error: SYM_ERROR): BOOLEAN
			-- Every app-server worker failure enters failure-driven retry handling.
		do
			Result := True
		end

	current_session_id: STRING_32
		local
			active_client: detachable SYM_APP_SERVER_CLIENT
		do
			active_client := active_client_snapshot
			if attached active_client as current_client then
				Result := session_id_for (current_client)
			else
				Result := saved_session_id
			end
		end

	session_id_for (a_client: SYM_APP_SERVER_CLIENT): STRING_32
		local
			locked, retried: BOOLEAN
		do
			if retried then
				Result := saved_session_id
			else
				client_stop_lock.lock
				locked := True
				if not a_client.session_id.is_empty then
					Result := a_client.session_id.twin
				else
					Result := saved_session_id
				end
				client_stop_lock.unlock
				locked := False
			end
		rescue
			if locked then client_stop_lock.unlock end
			retried := True
			retry
		end

	remember_session (a_client: SYM_APP_SERVER_CLIENT)
		local
			control_locked, stop_locked, retried: BOOLEAN
		do
			if not retried then
				client_stop_lock.lock
				stop_locked := True
				if not a_client.session_id.is_empty then
					control_lock.lock
					control_locked := True
					last_session_id := a_client.session_id.twin
					control_lock.unlock
					control_locked := False
				end
				client_stop_lock.unlock
				stop_locked := False
			end
		rescue
			if control_locked then control_lock.unlock end
			if stop_locked then client_stop_lock.unlock end
			retried := True
			retry
		end

	current_turn_count: INTEGER
		local
			active_client: detachable SYM_APP_SERVER_CLIENT
			locked, retried: BOOLEAN
		do
			if not retried then
				active_client := active_client_snapshot
				if attached active_client as current_client then
					client_stop_lock.lock
					locked := True
					Result := current_client.turn_count
					client_stop_lock.unlock
					locked := False
				end
			end
		rescue
			if locked then client_stop_lock.unlock end
			retried := True
			retry
		end

feature {NONE} -- Cleanup

	finish_attempt (a_workspace: SYM_WORKSPACE; a_identifier: READABLE_STRING_GENERAL;
		a_config: SYM_CONFIG)
			-- Stop the client, run `after_run' best effort, then remove terminal workspaces.
		local
			cleanup_error: SYM_ERROR
			retried: BOOLEAN
		do
			if not retried then
				if attached active_client_snapshot as active_client then
					remember_session (active_client)
					stop_client_safely (active_client)
					if attached active_client.last_error as termination_error then
						if attached outcome as current_outcome then
							create cleanup_error.make ("codex_termination_error", termination_error.message)
							create outcome.make_failure (cleanup_error, False, current_outcome.is_terminal,
								current_outcome.session_id, current_outcome.turn_count,
								current_outcome.latest_issue)
						else
							create cleanup_error.make ("codex_termination_error", termination_error.message)
							create outcome.make_failure (cleanup_error, False, False,
								saved_session_id, active_client.turn_count, Void)
						end
						-- Do not let the worker publish completion while its child can still
						-- mutate the workspace. The orchestrator therefore retains the claim.
						from until not active_client.has_live_process loop
							environment.sleep (250_000_000)
							stop_client_safely (active_client)
						end
					end
				end
				run_after_run_safely (a_workspace, a_config)
				if attached outcome as current_outcome and then current_outcome.is_terminal then
					workspace_manager.remove_for_issue (a_identifier, a_config)
					if attached workspace_manager.error as removal_error then
						create cleanup_error.make ("terminal_workspace_cleanup_failed",
							removal_error.code + ": " + removal_error.message)
						create outcome.make_failure (cleanup_error, False, True,
							current_outcome.session_id, current_outcome.turn_count,
							current_outcome.latest_issue)
					end
				end
			end
		rescue
			retried := True
			if attached outcome as current_outcome and then current_outcome.is_terminal then
				create cleanup_error.make ("terminal_workspace_cleanup_failed",
					"Unexpected terminal workspace cleanup failure")
				create outcome.make_failure (cleanup_error, False, True,
					current_outcome.session_id, current_outcome.turn_count,
					current_outcome.latest_issue)
			end
			retry
		end

	stop_client_safely (a_client: SYM_APP_SERVER_CLIENT)
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				client_stop_lock.lock
				locked := True
				a_client.stop_session
				client_stop_lock.unlock
				locked := False
			end
		rescue
			if locked then client_stop_lock.unlock end
			retried := True
			retry
		end

	run_after_run_safely (a_workspace: SYM_WORKSPACE; a_config: SYM_CONFIG)
		local
			retried: BOOLEAN
		do
			if not retried then
				workspace_manager.run_after_run (a_workspace, a_config)
			end
		rescue
			retried := True
			retry
		end

feature {NONE} -- Synchronized control state

	begin_run
			-- Publish a fresh running state while preserving a cancellation requested before `run'.
		local
			locked: BOOLEAN
		do
			control_lock.lock
			locked := True
			client := Void
			last_session_id.wipe_out
			is_running := True
			control_lock.unlock
			locked := False
		rescue
			if locked then control_lock.unlock end
		end

	publish_client (a_client: SYM_APP_SERVER_CLIENT)
		local
			locked: BOOLEAN
		do
			control_lock.lock
			locked := True
			client := a_client
			control_lock.unlock
			locked := False
		rescue
			if locked then control_lock.unlock end
		end

	set_running (a_value: BOOLEAN)
		local
			locked: BOOLEAN
		do
			control_lock.lock
			locked := True
			is_running := a_value
			control_lock.unlock
			locked := False
		rescue
			if locked then control_lock.unlock end
		end

	is_cancellation_requested: BOOLEAN
		local
			locked, retried: BOOLEAN
		do
			if retried then
				Result := True
			else
				control_lock.lock
				locked := True
				Result := cancel_requested
				control_lock.unlock
				locked := False
			end
		rescue
			if locked then control_lock.unlock end
			retried := True
			retry
		end

	active_client_snapshot: detachable SYM_APP_SERVER_CLIENT
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				control_lock.lock
				locked := True
				Result := client
				control_lock.unlock
				locked := False
			end
		rescue
			if locked then control_lock.unlock end
			retried := True
			retry
		end

	current_event_handler: detachable PROCEDURE [SYM_AGENT_EVENT]
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				control_lock.lock
				locked := True
				Result := event_handler
				control_lock.unlock
				locked := False
			end
		rescue
			if locked then control_lock.unlock end
			retried := True
			retry
		end

	saved_session_id: STRING_32
		local
			locked, retried: BOOLEAN
		do
			if retried then
				create Result.make_empty
			else
				control_lock.lock
				locked := True
				Result := last_session_id.twin
				control_lock.unlock
				locked := False
			end
		rescue
			if locked then control_lock.unlock end
			retried := True
			retry
		end

feature {NONE} -- Collaborators

	workspace_manager: SYM_WORKSPACE_MANAGER

	prompt_renderer: SYM_PROMPT_RENDERER

	event_handler: detachable PROCEDURE [SYM_AGENT_EVENT]

	cancel_requested: BOOLEAN

	last_session_id: STRING_32

	control_lock: MUTEX

	client_stop_lock: MUTEX

	strings: SYM_STRINGS
		once
			create Result
		end

	json: SYM_JSON
		once
			create Result
		end

	environment: EXECUTION_ENVIRONMENT
		once
			create Result
		end

invariant
	workspace_manager_attached: workspace_manager /= Void
	prompt_renderer_attached: prompt_renderer /= Void
	last_session_id_attached: last_session_id /= Void
	control_lock_attached: control_lock /= Void
	client_stop_lock_attached: client_stop_lock /= Void

end
