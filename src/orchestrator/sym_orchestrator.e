note
	description: "Single-authority Symphony polling, reconciliation, dispatch, and retry loop."

class
	SYM_ORCHESTRATOR

create
	make

feature {NONE} -- Initialization

	make (a_store: SYM_WORKFLOW_STORE; a_logger: SYM_LOGGER)
		do
			store := a_store
			logger := a_logger
			create factory
			create policy
			create running.make (10)
			create claimed.make (10)
			create retries.make (10)
			create completed.make (10)
			create stop_lock.make
			apply_workflow_candidate
		end

feature -- Status

	is_ready: BOOLEAN
		do
			Result := effective_workflow /= Void and then effective_config /= Void and then tracker /= Void and then last_error = Void
		end

	last_error: detachable SYM_ERROR

	running_count: INTEGER
		do
			Result := running.count
		end

	retrying_count: INTEGER
		do
			Result := retries.count
		end

	input_tokens, output_tokens, total_tokens: INTEGER_64

	seconds_running: INTEGER_64
			-- Aggregate elapsed worker time, including currently active workers.
		local
			now_ms, elapsed_ms: INTEGER_64
		do
			elapsed_ms := ended_runtime_ms
			now_ms := clock.monotonic_milliseconds
			across running as entry_cursor loop
				if now_ms > entry_cursor.item.worker.started_at_ms then
					elapsed_ms := elapsed_ms + now_ms - entry_cursor.item.worker.started_at_ms
				end
			end
			Result := elapsed_ms // 1_000
		end

	codex_rate_limits: detachable JSON_OBJECT
			-- Latest rate-limit payload observed across workers.

feature -- Service lifecycle

	run
		local
			next_poll_ms, now_ms, interval_ms: INTEGER_64
		do
			if not is_ready then
				log_current_error ("startup_failed", "Symphony startup validation failed")
			else
				startup_terminal_cleanup
				next_poll_ms := clock.monotonic_milliseconds
				from until is_stop_requested loop
					process_worker_exits (True)
					process_due_retries
					now_ms := clock.monotonic_milliseconds
					if now_ms >= next_poll_ms then
						reload_workflow
						reconcile_running (True)
						poll_and_dispatch (True)
						if attached effective_config as config then interval_ms := config.poll_interval_ms else interval_ms := 30_000 end
						next_poll_ms := clock.monotonic_milliseconds + interval_ms
					end
					environment.sleep (100_000_000)
				end
				shutdown_workers
			end
		rescue
			request_stop_safely
			shutdown_workers_safely
		end

	run_once
			-- Run one poll/reconciliation cycle, then wait for work started by it.
		local
			next_reconciliation_ms, now_ms: INTEGER_64
		do
			if not is_ready then
				log_current_error ("startup_failed", "Symphony validation failed")
			else
				startup_terminal_cleanup
				reload_workflow
				reconcile_running (False)
				poll_and_dispatch (False)
				next_reconciliation_ms := clock.monotonic_milliseconds
				from until running.is_empty loop
					now_ms := clock.monotonic_milliseconds
					if now_ms >= next_reconciliation_ms then
						reconcile_running (False)
						next_reconciliation_ms := clock.monotonic_milliseconds + run_once_reconciliation_interval_ms
					else
						process_worker_exits (False)
					end
					if not running.is_empty then
						environment.sleep (25_000_000)
					end
				end
				release_all_retries
			end
		rescue
			request_stop_safely
			shutdown_workers_safely
		end

	request_stop
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				stop_lock.lock
				locked := True
				stop_requested := True
				stop_lock.unlock
				locked := False
			end
		rescue
			if locked then stop_lock.unlock end
			retried := True
			retry
		end

feature {NONE} -- Workflow and preflight

	reload_workflow
		do
			store.reload_if_changed
			if attached store.last_error as workflow_error then
				last_error := workflow_error
				dispatch_blocked_by_reload := True
				logger.warning ("workflow_reload_failed", workflow_error.out, Void)
			else
				apply_workflow_candidate
				dispatch_blocked_by_reload := last_error /= Void
			end
		end

	apply_workflow_candidate
		local
			candidate_adapter: detachable SYM_TRACKER_ADAPTER
			must_replace_adapter: BOOLEAN
		do
			last_error := Void
			if attached store.workflow as workflow and attached store.config as config and then config.is_valid then
				must_replace_adapter := not attached effective_workflow as previous or else
					not previous.signature.same_string (workflow.signature)
				if must_replace_adapter or else tracker = Void then
					candidate_adapter := factory.new_adapter (config)
					if attached candidate_adapter as adapter then
						if attached tracker as gateway then gateway.replace_adapter (adapter) else create tracker.make (adapter) end
						effective_workflow := workflow
						effective_config := config
						logger.info ("workflow_applied", "Loaded effective workflow configuration", Void)
					else
						if attached factory.last_error as adapter_error then last_error := adapter_error else create last_error.make ("invalid_tracker_config", "Tracker adapter validation failed") end
						log_current_error ("workflow_rejected", "Retaining the last known good workflow")
					end
				else
					-- Rebuilds the typed config each defensive reload, even when content is unchanged.
					effective_workflow := workflow
					effective_config := config
				end
			elseif attached store.last_error as workflow_error then
				last_error := workflow_error
			elseif attached store.config as invalid_config and then attached invalid_config.error as config_error then
				last_error := config_error
			else
				create last_error.make ("invalid_workflow", "No valid workflow configuration is available")
			end
		end

feature {NONE} -- Polling and dispatch

	poll_and_dispatch (a_schedule_retries: BOOLEAN)
		local
			read: SYM_TRACKER_RESULT
			issues: ARRAYED_LIST [SYM_ISSUE]
		do
			if not dispatch_blocked_by_reload and then attached effective_config as config and attached effective_workflow as workflow and attached tracker as gateway then
				read := gateway.fetch_issues_by_states (config.active_states)
				if attached read.error as tracker_error then
					logger.warning ("tracker_candidate_fetch_failed", tracker_error.out, Void)
				else
					issues := policy.sorted_for_dispatch (read.issues)
					across issues as issue_cursor until running.count >= config.max_concurrent_agents loop
						if can_dispatch_candidate (issue_cursor.item, config) then
							dispatch (issue_cursor.item, 0, workflow, config, gateway,
								a_schedule_retries)
						end
					end
				end
			else
				log_current_error ("dispatch_validation_failed", "Skipping dispatch without an effective workflow and tracker")
			end
		end

	can_dispatch_candidate (a_issue: SYM_ISSUE; a_config: SYM_CONFIG): BOOLEAN
		do
			Result := policy.is_candidate (a_issue, a_config) and then not running.has (a_issue.id) and then
				not claimed.has (a_issue.id) and then running.count < a_config.max_concurrent_agents and then
				running_in_state (a_issue.state) < a_config.state_limit (a_issue.state)
		end

	dispatch (a_issue: SYM_ISSUE; a_attempt: INTEGER; a_workflow: SYM_WORKFLOW;
		a_config: SYM_CONFIG; a_tracker: SYM_TRACKER_GATEWAY; a_schedule_retries: BOOLEAN)
		local
			worker: detachable SYM_AGENT_WORKER
			entry: SYM_RUNNING_ENTRY
			attempt_ref: detachable INTEGER_64_REF
			context: SYM_LOG_CONTEXT
		do
			if a_attempt > 0 then create attempt_ref; attempt_ref.set_item (a_attempt) end
			create context.make_with_values (a_issue.id, a_issue.identifier, Void)
			claimed.force (True, a_issue.id)
			retries.remove (a_issue.id)
			worker := launched_worker (a_issue, attempt_ref, a_workflow, a_config, a_tracker)
			if attached worker as active_worker then
				create entry.make (a_issue, active_worker, a_attempt, a_config)
				running.force (entry, a_issue.id)
				logger.info ("issue_dispatched", "Started agent worker", context)
			elseif a_schedule_retries then
				schedule_failure_retry (a_issue.id, a_issue.identifier, a_issue.identifier,
					next_attempt (a_attempt), "failed to spawn agent", a_config)
			else
				claimed.remove (a_issue.id)
				logger.error ("worker_launch_failed", "Failed to spawn agent", context)
			end
		end

	launched_worker (a_issue: SYM_ISSUE; a_attempt: detachable INTEGER_64_REF; a_workflow: SYM_WORKFLOW; a_config: SYM_CONFIG; a_tracker: SYM_TRACKER_GATEWAY): detachable SYM_AGENT_WORKER
		local
			failed: BOOLEAN
			candidate: SYM_AGENT_WORKER
		do
			if not failed then
				create candidate.make (a_issue, a_attempt, a_workflow, a_config, a_tracker, logger)
				candidate.launch
				if candidate.is_last_launch_successful then
					Result := candidate
				end
			end
		rescue
			failed := True
			Result := Void
			retry
		end

feature {NONE} -- Worker completion

	process_worker_exits (a_schedule_retries: BOOLEAN)
		local
			ids: ARRAYED_LIST [STRING_32]
			entry: SYM_RUNNING_ENTRY
		do
			ids := running_ids
			across ids as id_cursor loop
				if running.has (id_cursor.item) then
					entry := running.definite_item (id_cursor.item)
					capture_worker_rate_limits (entry.worker)
					if entry.worker.join_with_timeout (0) then
						handle_worker_exit (id_cursor.item, entry, a_schedule_retries)
					end
				end
			end
		end

	handle_worker_exit (a_issue_id: STRING_32; a_entry: SYM_RUNNING_ENTRY; a_schedule_retries: BOOLEAN)
		local
			worker_outcome: detachable SYM_WORKER_OUTCOME
			context: SYM_LOG_CONTEXT
			message: STRING_32
		do
			capture_worker_rate_limits (a_entry.worker)
			running.remove (a_issue_id)
			input_tokens := input_tokens + a_entry.worker.input_tokens
			output_tokens := output_tokens + a_entry.worker.output_tokens
			total_tokens := total_tokens + a_entry.worker.total_tokens
			if clock.monotonic_milliseconds > a_entry.worker.started_at_ms then
				ended_runtime_ms := ended_runtime_ms + clock.monotonic_milliseconds - a_entry.worker.started_at_ms
			end
			worker_outcome := a_entry.worker.outcome_snapshot
			create context.make_with_values (a_issue_id, a_entry.issue.identifier, a_entry.worker.current_session_id)
			if a_entry.forced_terminal then
				cleanup_workspace (a_entry.workspace_identifier, a_entry.config)
				claimed.remove (a_issue_id)
				logger.info ("worker_stopped_terminal", a_entry.forced_reason, context)
			elseif not a_entry.forced_reason.is_empty then
				if a_entry.forced_retry and a_schedule_retries and attached effective_config as config then
					schedule_failure_retry (a_issue_id, a_entry.issue.identifier, a_entry.workspace_identifier,
						next_attempt (a_entry.retry_attempt), a_entry.forced_reason, config)
				else
					claimed.remove (a_issue_id)
				end
				logger.warning ("worker_stopped_by_reconciliation", a_entry.forced_reason, context)
			elseif attached worker_outcome as finished then
				if finished.is_terminal then
					claimed.remove (a_issue_id)
					if finished.is_failure then logger.error ("worker_terminal_cleanup_failed", finished.message, context) else logger.info ("worker_terminal", finished.message, context) end
				elseif finished.is_success then
					completed.force (True, a_issue_id)
					if a_schedule_retries and attached effective_config as config then
						schedule_continuation_retry (a_issue_id, a_entry.issue.identifier,
							a_entry.workspace_identifier, config)
					else
						claimed.remove (a_issue_id)
					end
					logger.info ("worker_completed", finished.message, context)
				elseif a_schedule_retries and finished.should_retry and attached effective_config as config then
					schedule_failure_retry (a_issue_id, a_entry.issue.identifier, a_entry.workspace_identifier,
						next_attempt (a_entry.retry_attempt), finished.message, config)
					logger.warning ("worker_failed_retrying", finished.message, context)
				else
					claimed.remove (a_issue_id)
					logger.error ("worker_failed", finished.message, context)
				end
			else
				message := "Worker terminated without an outcome"
				if a_schedule_retries and attached effective_config as config then
					schedule_failure_retry (a_issue_id, a_entry.issue.identifier, a_entry.workspace_identifier,
						next_attempt (a_entry.retry_attempt), message, config)
				else
					claimed.remove (a_issue_id)
				end
				logger.error ("worker_outcome_missing", message, context)
			end
		end

feature {NONE} -- Reconciliation

	reconcile_running (a_schedule_retries: BOOLEAN)
		local
			ids: ARRAYED_LIST [STRING_32]
			read: SYM_TRACKER_RESULT
			returned: HASH_TABLE [BOOLEAN, STRING_32]
			entry: SYM_RUNNING_ENTRY
			now_ms: INTEGER_64
		do
			process_worker_exits (a_schedule_retries)
			if not running.is_empty and attached effective_config as config and attached tracker as gateway then
				now_ms := clock.monotonic_milliseconds
				ids := running_ids
				if config.stall_timeout_ms > 0 then
					across ids as id_cursor loop
						if running.has (id_cursor.item) then
							entry := running.definite_item (id_cursor.item)
							if entry.forced_reason.is_empty and then now_ms - entry.worker.last_activity_milliseconds > config.stall_timeout_ms then
								entry.mark_forced_stop ("codex stall timeout", True, False)
								entry.worker.cancel
							end
						end
					end
				end
				read := gateway.fetch_issues_by_ids (ids)
				if attached read.error as tracker_error then
					logger.log_debug ("reconciliation_refresh_failed", tracker_error.out, Void)
				else
					create returned.make (ids.count)
					across read.issues as issue_cursor loop
						returned.force (True, issue_cursor.item.id)
						if running.has (issue_cursor.item.id) then
							entry := running.definite_item (issue_cursor.item.id)
							if config.is_terminal_state (issue_cursor.item.state) then
								entry.set_issue (issue_cursor.item)
								entry.mark_forced_stop ("issue entered terminal state", False, True)
								entry.worker.cancel
							elseif config.is_active_state (issue_cursor.item.state) and then policy.is_routable (issue_cursor.item, config) then
								entry.set_issue (issue_cursor.item)
							else
								entry.set_issue (issue_cursor.item)
								entry.mark_forced_stop ("issue is no longer active and routable", False, False)
								entry.worker.cancel
							end
						end
					end
					across ids as id_cursor loop
						if not returned.has (id_cursor.item) and then running.has (id_cursor.item) then
							entry := running.definite_item (id_cursor.item)
							entry.mark_forced_stop ("issue disappeared from tracker refresh", False, False)
							entry.worker.cancel
						end
					end
				end
			end
		end

feature {NONE} -- Retry queue

	schedule_continuation_retry (a_issue_id, a_identifier, a_workspace_identifier: STRING_32;
		a_config: SYM_CONFIG)
		do
			schedule_retry (a_issue_id, a_identifier, a_workspace_identifier, 1,
				policy.continuation_delay_ms, Void)
		end

	schedule_failure_retry (a_issue_id, a_identifier, a_workspace_identifier: STRING_32;
		a_attempt: INTEGER; a_error: READABLE_STRING_GENERAL; a_config: SYM_CONFIG)
		do
			schedule_retry (a_issue_id, a_identifier, a_workspace_identifier, a_attempt,
				policy.failure_delay_ms (a_attempt, a_config.max_retry_backoff_ms), a_error)
		end

	schedule_retry (a_issue_id, a_identifier, a_workspace_identifier: STRING_32;
		a_attempt: INTEGER; a_delay_ms: INTEGER_64; a_error: detachable READABLE_STRING_GENERAL)
		local
			entry: SYM_RETRY_ENTRY
			context: SYM_LOG_CONTEXT
		do
			create entry.make (a_issue_id, a_identifier, a_workspace_identifier, a_attempt,
				clock.monotonic_milliseconds + a_delay_ms, a_error)
			retries.force (entry, a_issue_id)
			claimed.force (True, a_issue_id)
			create context.make_with_values (a_issue_id, a_identifier, Void)
			logger.info ("retry_scheduled", "Retry attempt " + a_attempt.out + " in " + a_delay_ms.out + " ms", context)
		end

	process_due_retries
		local
			ids: ARRAYED_LIST [STRING_32]
			entry: SYM_RETRY_ENTRY
			read: SYM_TRACKER_RESULT
			issue: detachable SYM_ISSUE
			now_ms: INTEGER_64
		do
			now_ms := clock.monotonic_milliseconds
			create ids.make (retries.count)
			across retries as retry_cursor loop if retry_cursor.item.due_at_ms <= now_ms then ids.extend (retry_cursor.key.twin) end end
			if not ids.is_empty and then not dispatch_blocked_by_reload then
				-- A retry is a dispatch cycle too: preflight the workflow immediately
				-- before launching it, rather than waiting for the next poll tick.
				reload_workflow
			end
			if not ids.is_empty and then not dispatch_blocked_by_reload and then attached effective_config as config and attached effective_workflow as workflow and attached tracker as gateway then
				across ids as id_cursor loop
					if retries.has (id_cursor.item) then
						entry := retries.definite_item (id_cursor.item)
						retries.remove (id_cursor.item)
						read := gateway.fetch_issues_by_ids (single_id (id_cursor.item))
						if attached read.error as tracker_error then
							schedule_failure_retry (id_cursor.item, entry.identifier, entry.workspace_identifier,
								entry.attempt + 1, "retry refresh failed: " + tracker_error.out, config)
						else
							issue := issue_by_id (read.issues, id_cursor.item)
							if not attached issue as current_issue then
								claimed.remove (id_cursor.item)
							elseif config.is_terminal_state (current_issue.state) then
								cleanup_workspace (entry.workspace_identifier, config)
								claimed.remove (id_cursor.item)
							elseif not config.is_active_state (current_issue.state) or else not policy.is_routable (current_issue, config) then
								claimed.remove (id_cursor.item)
							elseif running.count >= config.max_concurrent_agents or else running_in_state (current_issue.state) >= config.state_limit (current_issue.state) then
								schedule_failure_retry (id_cursor.item, current_issue.identifier,
									entry.workspace_identifier, entry.attempt + 1,
									"no available orchestrator slots", config)
							else
								dispatch (current_issue, entry.attempt, workflow, config, gateway, True)
							end
						end
					end
				end
			end
		end

feature {NONE} -- Workspace cleanup and shutdown

	startup_terminal_cleanup
		local
			read: SYM_TRACKER_RESULT
		do
			if attached effective_config as config and attached tracker as gateway then
				read := gateway.fetch_issues_by_states (config.terminal_states)
				if attached read.error as tracker_error then
					logger.warning ("startup_cleanup_fetch_failed", tracker_error.out, Void)
				else
					across read.issues as issue_cursor loop
						cleanup_workspace (issue_cursor.item.identifier, config)
					end
				end
			end
		end

	cleanup_workspace (a_identifier: READABLE_STRING_GENERAL; a_config: SYM_CONFIG)
		local
			manager: SYM_WORKSPACE_MANAGER
			context: SYM_LOG_CONTEXT
		do
			create manager.make
			manager.remove_for_issue (a_identifier, a_config)
			create context.make_with_values (Void, a_identifier, Void)
			if attached manager.warning as hook_warning then
				logger.warning ("workspace_hook_failed", hook_warning.out, context)
			end
			if attached manager.error as cleanup_error then
				logger.warning ("workspace_cleanup_failed", cleanup_error.out, context)
			end
		end

	shutdown_workers
		local
			ids: ARRAYED_LIST [STRING_32]
			entry: SYM_RUNNING_ENTRY
			context: SYM_LOG_CONTEXT
			shutdown_error: SYM_ERROR
			joined, warned: BOOLEAN
		do
			ids := running_ids
			across ids as id_cursor loop
				if running.has (id_cursor.item) then running.definite_item (id_cursor.item).worker.cancel end
			end
			across ids as id_cursor loop
				if running.has (id_cursor.item) then
					entry := running.definite_item (id_cursor.item)
					joined := entry.worker.join_with_timeout (shutdown_join_timeout_ms)
					warned := False
					from until joined loop
						if not warned then
							create context.make_with_values (id_cursor.item, entry.issue.identifier,
								entry.worker.current_session_id)
							logger.warning ("worker_shutdown_timeout",
								"Worker remains owned while process-group termination continues", context)
							create shutdown_error.make ("worker_shutdown_timeout",
								"A worker exceeded the graceful shutdown timeout")
							last_error := shutdown_error
							warned := True
						end
						entry.worker.cancel
						joined := entry.worker.join_with_timeout (shutdown_join_timeout_ms)
					end
					capture_worker_rate_limits (entry.worker)
					input_tokens := input_tokens + entry.worker.input_tokens
					output_tokens := output_tokens + entry.worker.output_tokens
					total_tokens := total_tokens + entry.worker.total_tokens
					if clock.monotonic_milliseconds > entry.worker.started_at_ms then
						ended_runtime_ms := ended_runtime_ms + clock.monotonic_milliseconds - entry.worker.started_at_ms
					end
					running.remove (id_cursor.item)
					claimed.remove (id_cursor.item)
				end
			end
			release_all_retries
		end

	shutdown_workers_safely
			-- Attempt shutdown without replacing an exception already being propagated.
		local
			retried: BOOLEAN
		do
			if not retried then
				shutdown_workers
			end
		rescue
			retried := True
			retry
		end

	release_all_retries
		do
			across retries as retry_cursor loop claimed.remove (retry_cursor.key) end
			retries.wipe_out
		end

	capture_worker_rate_limits (a_worker: SYM_AGENT_WORKER)
		local
			updated_at: INTEGER_64
		do
			updated_at := a_worker.rate_limit_update_milliseconds
			if updated_at > 0 and then updated_at >= rate_limit_update_ms and then
				attached a_worker.current_rate_limits as limits and then
				attached {JSON_OBJECT} json.cloned (limits) as copied_limits
			then
				codex_rate_limits := copied_limits
				rate_limit_update_ms := updated_at
			end
		end

feature {NONE} -- Queries and helpers

	is_stop_requested: BOOLEAN
		local
			locked, retried: BOOLEAN
		do
			if retried then
				Result := True
			else
				stop_lock.lock
				locked := True
				Result := stop_requested
				stop_lock.unlock
				locked := False
			end
		rescue
			if locked then stop_lock.unlock end
			retried := True
			retry
		end

	request_stop_safely
			-- Set the shared stop flag without replacing an exception in flight.
		local
			retried: BOOLEAN
		do
			if not retried then
				request_stop
			end
		rescue
			retried := True
			retry
		end

	running_in_state (a_state: READABLE_STRING_GENERAL): INTEGER
		local
			normalized_state: STRING_32
		do
			normalized_state := strings.normalized (a_state)
			across running as entry_cursor loop
				if entry_cursor.item.issue.normalized_state.same_string (normalized_state) then Result := Result + 1 end
			end
		end

	running_ids: ARRAYED_LIST [STRING_32]
		do
			create Result.make (running.count)
			across running as entry_cursor loop Result.extend (entry_cursor.key.twin) end
		end

	single_id (a_id: STRING_32): ARRAYED_LIST [STRING_32]
		do
			create Result.make (1)
			Result.extend (a_id)
		end

	issue_by_id (a_issues: ITERABLE [SYM_ISSUE]; a_id: READABLE_STRING_GENERAL): detachable SYM_ISSUE
		do
			across a_issues as issue_cursor until Result /= Void loop
				if issue_cursor.item.id.same_string_general (a_id) then Result := issue_cursor.item end
			end
		end

	next_attempt (a_previous: INTEGER): INTEGER
		do
			if a_previous > 0 then Result := a_previous + 1 else Result := 1 end
		end

	log_current_error (a_event, a_fallback: READABLE_STRING_GENERAL)
		do
			if attached last_error as current_error then logger.error (a_event, current_error.out, Void) else logger.error (a_event, a_fallback, Void) end
		end

feature {NONE} -- State

	store: SYM_WORKFLOW_STORE

	logger: SYM_LOGGER

	factory: SYM_TRACKER_FACTORY

	policy: SYM_DISPATCH_POLICY

	effective_workflow: detachable SYM_WORKFLOW

	effective_config: detachable SYM_CONFIG

	tracker: detachable SYM_TRACKER_GATEWAY

	running: HASH_TABLE [SYM_RUNNING_ENTRY, STRING_32]

	claimed, completed: HASH_TABLE [BOOLEAN, STRING_32]

	retries: HASH_TABLE [SYM_RETRY_ENTRY, STRING_32]

	ended_runtime_ms: INTEGER_64

	rate_limit_update_ms: INTEGER_64

	dispatch_blocked_by_reload: BOOLEAN

	stop_requested: BOOLEAN

	stop_lock: MUTEX

	shutdown_join_timeout_ms: NATURAL_64 = 5_000

	run_once_reconciliation_interval_ms: INTEGER_64 = 1_000

	clock: SYM_CLOCK
		once
			create Result
		end

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

end
