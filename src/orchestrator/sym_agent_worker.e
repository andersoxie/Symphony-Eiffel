note
	description: "One background thread running a synchronous Symphony agent attempt."

class
	SYM_AGENT_WORKER

inherit
	THREAD
		rename
			make as thread_make
		end

create
	make

feature {NONE} -- Initialization

	make (
		a_issue: SYM_ISSUE;
		a_attempt: detachable INTEGER_64_REF;
		a_workflow: SYM_WORKFLOW;
		a_config: SYM_CONFIG;
		a_tracker: SYM_TRACKER_GATEWAY;
		a_logger: SYM_LOGGER
	)
		do
			thread_make
			issue := a_issue
			if attached a_attempt as value then attempt := value.twin end
			workflow := a_workflow
			config := a_config
			tracker := a_tracker
			logger := a_logger
			create state_lock.make
			create session_id.make_empty
			create last_event.make_empty
			started_at_ms := clock.monotonic_milliseconds
			last_activity_ms := started_at_ms
		end

feature -- Status snapshots

	started_at_ms: INTEGER_64

	last_activity_milliseconds: INTEGER_64
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				Result := last_activity_ms
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	current_session_id: STRING_32
		local
			locked, retried: BOOLEAN
		do
			if retried then
				create Result.make_empty
			else
				state_lock.lock
				locked := True
				Result := session_id.twin
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	current_turn_count: INTEGER
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				Result := turn_count
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	last_event_name: STRING_32
		local
			locked, retried: BOOLEAN
		do
			if retried then
				create Result.make_empty
			else
				state_lock.lock
				locked := True
				Result := last_event.twin
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	input_tokens: INTEGER_64
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				Result := input_token_count
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	output_tokens: INTEGER_64
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				Result := output_token_count
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	total_tokens: INTEGER_64
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				Result := total_token_count
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	current_rate_limits: detachable JSON_OBJECT
			-- Most recent rate-limit payload observed by this worker.
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				Result := rate_limit_value
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	rate_limit_update_milliseconds: INTEGER_64
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				Result := rate_limit_update_ms
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	outcome_snapshot: detachable SYM_WORKER_OUTCOME
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				Result := outcome
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

feature -- Control

	cancel
		local
			active_runner: detachable SYM_AGENT_RUNNER
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				cancel_requested := True
				active_runner := runner
				state_lock.unlock
				locked := False
				if attached active_runner as value then value.cancel end
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

feature {NONE} -- Thread execution

	execute
		local
			new_runner: SYM_AGENT_RUNNER
			cancel_now, locked, retried: BOOLEAN
		do
			if not retried then
				create new_runner.make
				state_lock.lock
				locked := True
				runner := new_runner
				cancel_now := cancel_requested
				state_lock.unlock
				locked := False
				new_runner.set_event_handler (agent receive_event)
				if cancel_now then new_runner.cancel end
				new_runner.run (issue, attempt, workflow, config, tracker)
				state_lock.lock
				locked := True
				outcome := new_runner.outcome
				if attached outcome as final_outcome then
					session_id := final_outcome.session_id.twin
					turn_count := final_outcome.turn_count
				end
				runner := Void
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then
				state_lock.unlock
				locked := False
			end
			record_unexpected_failure_safely
			retried := True
			retry
		end

	receive_event (a_event: SYM_AGENT_EVENT)
		local
			context: SYM_LOG_CONTEXT
			fields: JSON_OBJECT
			message: STRING_32
			current_session: STRING_32
			current_input, current_output, current_total: INTEGER_64
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				last_activity_ms := clock.monotonic_milliseconds
				last_event := a_event.event.twin
				if a_event.event.same_string ("session_started") and attached a_event.message as value then
					session_id := value.twin
					turn_count := turn_count + 1
				elseif a_event.total_tokens > 0 or else a_event.input_tokens > 0 or else a_event.output_tokens > 0 then
					input_token_count := a_event.input_tokens
					output_token_count := a_event.output_tokens
					total_token_count := a_event.total_tokens
				end
				if attached a_event.rate_limits as limits and then attached {JSON_OBJECT} json.cloned (limits) as copied_limits then
					rate_limit_value := copied_limits
					rate_limit_update_ms := last_activity_ms
				end
				current_session := session_id.twin
				current_input := input_token_count
				current_output := output_token_count
				current_total := total_token_count
				state_lock.unlock
				locked := False
				create context.make_with_values (issue.id, issue.identifier, current_session)
				create fields.make_empty
				if attached a_event.codex_app_server_pid as pid then fields.put_string (pid, "codex_app_server_pid") end
				fields.put_integer (current_input, "input_tokens")
				fields.put_integer (current_output, "output_tokens")
				fields.put_integer (current_total, "total_tokens")
				if attached a_event.message as value then message := value else message := a_event.event end
				logger.info_with_fields (a_event.event, message, context, fields)
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

	record_unexpected_failure_safely
			-- Publish a retryable worker outcome without allowing rescue cleanup to fail.
		local
			locked, retried: BOOLEAN
		do
			if not retried then
				state_lock.lock
				locked := True
				if outcome = Void then
					outcome := create {SYM_WORKER_OUTCOME}.make_failure (
						create {SYM_ERROR}.make ("worker_thread_error", "Unexpected worker thread failure"),
						True, False, session_id, turn_count, issue)
				end
				runner := Void
				state_lock.unlock
				locked := False
			end
		rescue
			if locked then state_lock.unlock end
			retried := True
			retry
		end

feature {NONE} -- Attempt snapshot

	issue: SYM_ISSUE

	attempt: detachable INTEGER_64_REF

	workflow: SYM_WORKFLOW

	config: SYM_CONFIG

	tracker: SYM_TRACKER_GATEWAY

	logger: SYM_LOGGER

	runner: detachable SYM_AGENT_RUNNER

	outcome: detachable SYM_WORKER_OUTCOME

	state_lock: MUTEX

	cancel_requested: BOOLEAN

	last_activity_ms: INTEGER_64

	session_id, last_event: STRING_32

	turn_count: INTEGER

	input_token_count, output_token_count, total_token_count: INTEGER_64

	rate_limit_value: detachable JSON_OBJECT

	rate_limit_update_ms: INTEGER_64

	json: SYM_JSON once create Result end

	clock: SYM_CLOCK
		once
			create Result
		end

end
