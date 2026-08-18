note
	description: "Version-aware Codex app-server JSONL client implementing the Symphony session contract."

class
	SYM_APP_SERVER_CLIENT

create
	make

feature {NONE} -- Initialization

	make
		do
			create transport.make
			create thread_id.make_empty
			create turn_id.make_empty
			create session_id.make_empty
		ensure
			thread_not_started: thread_id.is_empty
			turn_not_started: turn_id.is_empty
			session_not_started: session_id.is_empty
			no_completed_turns: turn_count = 0
			no_error: last_error = Void
			no_event: last_event = Void
			not_started: not is_started
			no_live_process: not has_live_process
		end

feature -- Session state

	thread_id: STRING_32

	turn_id: STRING_32

	session_id: STRING_32

	turn_count: INTEGER

	last_error: detachable SYM_ERROR

	last_event: detachable SYM_AGENT_EVENT

	event_handler: detachable PROCEDURE [SYM_AGENT_EVENT]

	is_started: BOOLEAN
		do
			Result := not thread_id.is_empty and transport.is_running
		ensure
			started_definition: Result = (not thread_id.is_empty and transport.is_running)
		end

	has_live_process: BOOLEAN
			-- Does this client still own an app-server process that has not exited?
		do
			Result := transport.has_live_processes
		ensure
			live_process_definition: Result = transport.has_live_processes
		end

	set_event_handler (a_handler: detachable PROCEDURE [SYM_AGENT_EVENT])
		do
			event_handler := a_handler
		ensure
			handler_set: event_handler = a_handler
		end

feature -- Lifecycle

	start_session (a_workspace: SYM_WORKSPACE; a_config: SYM_CONFIG; a_secret_names: ITERABLE [STRING_32])
		require
			idle: not has_live_process
			valid_config: a_config.is_valid
		local
			request, params, capabilities, client_info: JSON_OBJECT
		do
			last_error := Void
			transport.start (a_config.codex_command, a_workspace.path, a_config.workspace_root, a_secret_names)
			if attached transport.last_error as e then
				fail ("startup_failed", e)
			else
				create request.make_empty
				request.put_string ("initialize", "method")
				request.put_integer (1, "id")
				create params.make_empty
				create capabilities.make_empty
				capabilities.put_boolean (True, "experimentalApi")
				params.put (capabilities, "capabilities")
				create client_info.make_empty
				client_info.put_string ("symphony_eiffel", "name")
				client_info.put_string ("Symphony Eiffel", "title")
				client_info.put_string ("0.1.0", "version")
				params.put (client_info, "clientInfo")
				request.put (params, "params")
				transport.send (request)
				wait_response (1, a_config.read_timeout_ms)
				if last_error = Void then
					send_initialized
					start_thread (a_workspace, a_config)
				end
			end
		ensure
			thread_started_or_error: last_error /= Void or else not thread_id.is_empty
			turn_count_unchanged: turn_count = old turn_count
		end

	stop_session
		do
			last_error := Void
			transport.stop
			if attached transport.last_error as termination_error then
				last_error := termination_error
			else
				thread_id.wipe_out
				turn_id.wipe_out
				session_id.wipe_out
			end
		ensure
			stopped_or_error: last_error /= Void or else
				(not has_live_process and thread_id.is_empty and turn_id.is_empty and session_id.is_empty)
		rescue
			create last_error.make ("codex_termination_error",
				"Unexpected failure while stopping app-server session")
		end

feature -- Turns

	run_turn (a_prompt: READABLE_STRING_GENERAL; a_issue: SYM_ISSUE; a_workspace: SYM_WORKSPACE; a_config: SYM_CONFIG)
		require
			valid_issue: a_issue.is_core_valid
			valid_config: a_config.is_valid
			workspace_is_direct_child: a_workspace.path.parent.canonical_path.is_equal (
				a_config.workspace_root.canonical_path)
		local
			request, params, input_item: JSON_OBJECT
			input: JSON_ARRAY
		do
			last_error := Void
			if not is_started then
				create last_error.make ("codex_session_error", "Cannot start a turn before the session handshake")
			else
				create request.make_empty
				request.put_string ("turn/start", "method")
				request.put_integer (3, "id")
				create params.make_empty
				params.put_string (thread_id, "threadId")
				create input.make_empty
				create input_item.make_empty
				input_item.put_string ("text", "type")
				input_item.put_string (a_prompt, "text")
				input.extend (input_item)
				params.put (input, "input")
				params.put_string (a_workspace.path.canonical_path.name, "cwd")
				params.put_string (a_issue.identifier + ": " + a_issue.title, "title")
				params.put (json.cloned (a_config.approval_policy), "approvalPolicy")
				if attached a_config.turn_sandbox_policy as policy then
					params.put (sandbox_policy_for (policy, a_workspace.path), "sandboxPolicy")
				end
				request.put (params, "params")
				transport.send (request)
				wait_turn_start (a_config.read_timeout_ms)
				if last_error = Void then
					turn_count := turn_count + 1
					emit ("session_started", session_id)
					stream_turn (a_config)
				end
			end
		ensure
			turn_count_monotonic: turn_count >= old turn_count
			at_most_one_turn_started: turn_count <= old turn_count + 1
			started_turn_has_identity: turn_count > old turn_count implies
				(not turn_id.is_empty and not session_id.is_empty)
		end

feature {NONE} -- Handshake

	send_initialized
		local
			n, p: JSON_OBJECT
		do
			create n.make_empty
			n.put_string ("initialized", "method")
			create p.make_empty
			n.put (p, "params")
			transport.send (n)
		end

	start_thread (a_workspace: SYM_WORKSPACE; a_config: SYM_CONFIG)
		local
			request, params: JSON_OBJECT
		do
			create request.make_empty
			request.put_string ("thread/start", "method")
			request.put_integer (2, "id")
			create params.make_empty
			params.put_string (a_workspace.path.canonical_path.name, "cwd")
			params.put (json.cloned (a_config.approval_policy), "approvalPolicy")
			params.put (json.cloned (a_config.thread_sandbox), "sandbox")
			params.put_string ("symphony_eiffel", "serviceName")
			request.put (params, "params")
			transport.send (request)
			wait_response (2, a_config.read_timeout_ms)
			if last_error = Void and attached response as r and then attached json.object (r, "result") as result_object and then
				attached json.object (result_object, "thread") as thread and then attached json.string (thread, "id") as id
			then
				thread_id := id
			else
				fail ("startup_failed", create {SYM_ERROR}.make ("codex_protocol_error", "thread/start response has no thread.id"))
			end
		end

	wait_turn_start (a_timeout_ms: INTEGER_64)
		do
			wait_response (3, a_timeout_ms)
			if last_error = Void and attached response as r and then attached json.object (r, "result") as result_object and then
				attached json.object (result_object, "turn") as turn and then attached json.string (turn, "id") as id
			then
				turn_id := id
				session_id := thread_id + "-" + turn_id
			else
				create last_error.make ("codex_protocol_error", "turn/start response has no turn.id")
			end
		end

	wait_response (a_id: INTEGER_64; a_timeout_ms: INTEGER_64)
		local
			done: BOOLEAN
			started_at_ms, elapsed_ms, remaining_ms: INTEGER_64
		do
			response := Void
			started_at_ms := clock.monotonic_milliseconds
			from until done loop
				elapsed_ms := clock.monotonic_milliseconds - started_at_ms
				if elapsed_ms >= a_timeout_ms then
					create last_error.make ("codex_timeout", "App-server response was not received before the configured timeout")
					done := True
				else
					remaining_ms := a_timeout_ms - elapsed_ms
					transport.next_message_with_absolute_timeout (remaining_ms)
					if attached transport.last_error as e then
						last_error := e
						done := True
					elseif attached transport.last_message as m then
						if message_id (m) = a_id then
							if attached m.item ("error") as response_error then
								-- App-server error objects can contain echoed request data or
								-- provider diagnostics. Keep that untrusted payload out of the
								-- propagated error because worker errors are written to logs.
								create last_error.make ("codex_protocol_error", "App-server returned an error response")
							else
								response := m
							end
							done := True
						else
							handle_async_message (m, Void)
						end
					end
				end
			end
		end

feature {NONE} -- Streaming

	stream_turn (a_config: SYM_CONFIG)
		local
			done: BOOLEAN
			method: detachable STRING_32
		do
			from until done loop
				transport.next_message (a_config.turn_timeout_ms)
				if attached transport.last_error as e then
					last_error := e
					emit ("turn_ended_with_error", e.message)
					done := True
				elseif attached transport.last_message as m then
					method := json.string (m, "method")
					if attached method as name and then name.same_string ("turn/completed") then
						if turn_completed_successfully (m) then emit ("turn_completed", Void) else create last_error.make ("codex_turn_failed", "turn/completed reported a non-completed status"); emit ("turn_failed", Void) end
						done := True
					elseif attached method as name and then (name.same_string ("turn/failed") or name.same_string ("turn/cancelled")) then
						create last_error.make ("codex_turn_failed", name)
						emit (if name.ends_with ("cancelled") then "turn_cancelled" else "turn_failed" end, Void)
						done := True
					else
						handle_async_message (m, a_config)
						if last_error /= Void then done := True end
					end
				end
			end
		end

	handle_async_message (a_message: JSON_OBJECT; a_config: detachable SYM_CONFIG)
		local
			method: detachable STRING_32
		do
			method := json.string (a_message, "method")
			if attached method as name then
				if is_approval_method (name) and then has_request_id (a_message) then
					handle_approval (a_message, name, a_config)
				elseif name.same_string ("item/tool/requestUserInput") or name.same_string ("mcpServer/elicitation/request") then
					reply_request_error (a_message, -32_002, "Symphony Eiffel does not provide interactive user input")
					create last_error.make ("codex_input_required", "App-server requested interactive input")
					emit ("turn_input_required", name)
				elseif name.same_string ("item/permissions/requestApproval") then
					reply_request_error (a_message, -32_002, "Symphony Eiffel does not grant additional runtime permissions")
					create last_error.make ("codex_approval_required", "App-server requested additional permissions")
					emit ("approval_required", name)
				elseif name.same_string ("item/tool/call") then
					reply_unsupported_tool (a_message)
					emit ("unsupported_tool_call", Void)
				elseif name.same_string ("thread/tokenUsage/updated") then
					emit_usage (a_message)
				elseif name.has_substring ("rateLimit") or name.has_substring ("rate_limits") then
					emit_rate_limits (a_message)
				elseif has_request_id (a_message) then
					reply_request_error (a_message, -32_601, "Unsupported app-server request method")
					create last_error.make ("codex_unsupported_request", "Unsupported app-server request: " + name)
					emit ("unsupported_request", name)
				else
					emit ("notification", name)
				end
			else
				-- Do not log an unclassified protocol payload. It may contain
				-- prompt text, tool arguments, credentials, or provider data.
				emit ("other_message", "Unclassified app-server message")
			end
		end

	handle_approval (a_message: JSON_OBJECT; a_method: STRING_32; a_config: detachable SYM_CONFIG)
		local
			decision: STRING_8
		do
			if attached a_config as cfg and then attached {JSON_STRING} cfg.approval_policy as p and then p.same_string ("never") then
				if a_method.same_string ("execCommandApproval") or a_method.same_string ("applyPatchApproval") then decision := "approved_for_session" else decision := "acceptForSession" end
				reply_decision (a_message, decision)
				emit ("approval_auto_approved", a_method)
			else
				if a_method.same_string ("execCommandApproval") or a_method.same_string ("applyPatchApproval") then decision := "abort" else decision := "cancel" end
				reply_decision (a_message, decision)
				create last_error.make ("codex_approval_required", "Approval requested under non-auto-approve policy")
				emit ("approval_required", a_method)
			end
		end

feature {NONE} -- Responses and telemetry

	reply_decision (a_request: JSON_OBJECT; a_decision: STRING_8)
		local
			r, response_result: JSON_OBJECT
		do
			create r.make_empty
			put_request_id (r, a_request)
			create response_result.make_empty
			response_result.put_string (a_decision, "decision")
			r.put (response_result, "result")
			transport.send (r)
		end

	reply_request_error (a_request: JSON_OBJECT; a_code: INTEGER_64; a_message: READABLE_STRING_GENERAL)
		local
			r, e: JSON_OBJECT
		do
			create r.make_empty
			put_request_id (r, a_request)
			create e.make_empty
			e.put_integer (a_code, "code")
			e.put_string (a_message, "message")
			r.put (e, "error")
			transport.send (r)
		end

	reply_unsupported_tool (a_request: JSON_OBJECT)
		local
			r, response_result, content_item: JSON_OBJECT
			content_items: JSON_ARRAY
		do
			create r.make_empty
			put_request_id (r, a_request)
			create response_result.make_empty
			response_result.put_boolean (False, "success")
			create content_items.make_empty
			create content_item.make_empty
			content_item.put_string ("inputText", "type")
			content_item.put_string ("Unsupported dynamic tool", "text")
			content_items.extend (content_item)
			response_result.put (content_items, "contentItems")
			r.put (response_result, "result")
			transport.send (r)
		end

	emit_usage (a_message: JSON_OBJECT)
		local
			e: SYM_AGENT_EVENT
			input, output, total: INTEGER_64
			absolute: JSON_OBJECT
		do
			if attached json.object (a_message, "params") as params and then attached json.object (params, "tokenUsage") as usage then
				-- Current app-server schemas expose cumulative counts in
				-- tokenUsage.total and per-turn deltas in tokenUsage.last.
				-- Accept the earlier flat shape too, but never aggregate `last'.
				if attached json.object (usage, "total") as total_usage then
					absolute := total_usage
				else
					absolute := usage
				end
				input := usage_count (absolute, "inputTokens", "input_tokens")
				output := usage_count (absolute, "outputTokens", "output_tokens")
				total := usage_count (absolute, "totalTokens", "total_tokens")
				create e.make ("notification", transport.process_id, "thread/tokenUsage/updated")
				e.set_usage (input, output, total)
				deliver (e)
			end
		end

	emit_rate_limits (a_message: JSON_OBJECT)
		local
			e: SYM_AGENT_EVENT
		do
			create e.make ("notification", transport.process_id, json.string (a_message, "method"))
			if attached json.object (a_message, "params") as params then e.set_rate_limits (params) end
			deliver (e)
		end

	usage_count (a_usage: JSON_OBJECT; a_primary_key, a_legacy_key: READABLE_STRING_8): INTEGER_64
		do
			if attached json.integer_64 (a_usage, a_primary_key) as n then
				Result := n.item
			elseif attached json.integer_64 (a_usage, a_legacy_key) as n then
				Result := n.item
			end
		end

	emit (a_event: READABLE_STRING_GENERAL; a_message: detachable READABLE_STRING_GENERAL)
		local
			e: SYM_AGENT_EVENT
		do
			create e.make (a_event, transport.process_id, a_message)
			deliver (e)
		end

	deliver (a_event: SYM_AGENT_EVENT)
		do
			last_event := a_event
			if attached event_handler as h then h.call ([a_event]) end
		end

feature {NONE} -- Message helpers

	response: detachable JSON_OBJECT

	message_id (a_message: JSON_OBJECT): INTEGER_64
		do
			Result := -1
			if attached json.integer_64 (a_message, "id") as n then Result := n.item end
		end

	has_request_id (a_message: JSON_OBJECT): BOOLEAN
		do
			Result := attached {JSON_STRING} a_message.item ("id") or else
				(attached {JSON_NUMBER} a_message.item ("id") as number and then number.item.is_integer_64)
		end

	put_request_id (a_response, a_request: JSON_OBJECT)
		do
			if attached a_request.item ("id") as request_id then
				a_response.put (json.cloned (request_id), "id")
			else
				a_response.put (Void, "id")
			end
		end

	is_approval_method (a_method: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := a_method.same_string ("item/commandExecution/requestApproval") or else
				a_method.same_string ("item/fileChange/requestApproval") or else
				a_method.same_string ("execCommandApproval") or else a_method.same_string ("applyPatchApproval")
		end

	turn_completed_successfully (a_message: JSON_OBJECT): BOOLEAN
		do
			Result := True
			if attached json.object (a_message, "params") as params and then attached json.object (params, "turn") as turn and then attached json.string (turn, "status") as status then
				Result := status.same_string ("completed")
			end
		end

	sandbox_policy_for (a_policy: JSON_VALUE; a_workspace: PATH): JSON_VALUE
		local
			o: JSON_OBJECT
			a: JSON_ARRAY
		do
			Result := json.cloned (a_policy)
			if attached {JSON_OBJECT} Result as policy_object and then attached json.string (policy_object, "type") as kind and then kind.same_string ("workspaceWrite") then
				o := policy_object
				if not o.has_key ("writableRoots") then
					create a.make_empty
					a.extend (create {JSON_STRING}.make_from_string_general (a_workspace.canonical_path.name))
					o.put (a, "writableRoots")
				end
			end
		end

	fail (a_event: READABLE_STRING_GENERAL; a_error: SYM_ERROR)
		do
			last_error := a_error
			emit (a_event, a_error.message)
		end

feature {NONE} -- Collaborators

	transport: SYM_CODEX_TRANSPORT

	json: SYM_JSON once create Result end

	clock: SYM_CLOCK once create Result end

end
