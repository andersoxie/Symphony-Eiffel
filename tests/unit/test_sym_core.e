note
	testing: "execution/serial/symphony"

class
	TEST_SYM_CORE

inherit
	EQA_TEST_SET

feature -- Hash/path tests

	test_sha_256
		local
			h: SYM_HASH
		do
			create h
			assert ("sha256 abc", h.sha_256_hex ("abc").same_string ("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
		end

	test_workspace_key_collision_resistance
		local
			p: SYM_PATH_SAFETY
			first, second, dot_key: STRING_32
		do
			create p
			assert ("safe unchanged", p.workspace_key ("EIFFEL-42").same_string ("EIFFEL-42"))
			first := p.workspace_key ("TEAM/A")
			second := p.workspace_key ("TEAM?A")
			assert ("sanitized", first.starts_with ("TEAM_A-") and second.starts_with ("TEAM_A-"))
			assert ("distinct", not first.same_string (second))
			assert ("safe", p.is_safe_key (first) and p.is_safe_key (second))
			dot_key := p.workspace_key ("..")
			assert ("parent component disambiguated", not dot_key.same_string ("..") and p.is_safe_key (dot_key))
			if {PLATFORM}.is_windows then
				assert ("trailing dot disambiguated", not p.workspace_key ("EIFFEL-42.").same_string ("EIFFEL-42."))
				assert ("device name disambiguated", not p.workspace_key ("CON.txt").same_string ("CON.txt"))
			end
		end

	test_jsonl_complete_line_limit
		local
			inbox: SYM_JSONL_INBOX
			oversized: STRING_8
		do
			create inbox.make
			create oversized.make_filled ('x', 10_485_761)
			oversized.append_character ('%N')
			inbox.append_stdout (oversized)
			assert ("complete oversized line rejected", inbox.has_overflowed)
			assert ("oversized line not queued", inbox.next_line = Void)
		end

feature -- Configuration tests

	test_config_defaults
		local
			root, tracker: JSON_OBJECT
			active, terminal: JSON_ARRAY
			workflow: SYM_WORKFLOW
			config: SYM_CONFIG
			path: PATH
		do
			create root.make_empty
			create tracker.make_empty
			tracker.put_string ("memory", "kind")
			create active.make_empty
			active.extend (create {JSON_STRING}.make_from_string ("Todo"))
			tracker.put (active, "active_states")
			create terminal.make_empty
			terminal.extend (create {JSON_STRING}.make_from_string ("Done"))
			tracker.put (terminal, "terminal_states")
			root.put (tracker, "tracker")
			create path.make_from_string ("WORKFLOW.md")
			create workflow.make (root, "{{ issue.title }}", path.absolute_path, "test")
			create config.make (workflow)
			assert ("valid", config.is_valid)
			assert ("poll default", config.poll_interval_ms = 30_000)
			assert ("hooks default", config.hook_timeout_ms = 60_000)
			assert ("turns default", config.max_turns = 20)
			assert ("active normalization", config.is_active_state (" todo "))
			assert ("terminal normalization", config.is_terminal_state ("DONE"))
		end

	test_blank_workspace_root_is_rejected
		local
			root, workspace: JSON_OBJECT
			workflow: SYM_WORKFLOW
			config: SYM_CONFIG
			path: PATH
		do
			root := base_memory_config
			create workspace.make_empty
			workspace.put_string ("", "root")
			root.put (workspace, "workspace")
			create path.make_from_string ("WORKFLOW.md")
			create workflow.make (root, "prompt", path.absolute_path, "blank-root")
			create config.make (workflow)
			assert ("blank root invalid", not config.is_valid)
			assert ("typed root error", attached config.error as e and then e.code.same_string ("invalid_workspace_root"))
		end

feature -- Model/adapter tests

	test_issue_codec_and_memory_tracker
		local
			o: JSON_OBJECT
			labels: JSON_ARRAY
			codec: SYM_ISSUE_CODEC
			tracker: SYM_MEMORY_TRACKER
			states, ids: ARRAYED_LIST [STRING_32]
		do
			create o.make_empty
			o.put_string ("opaque-1", "id")
			o.put_string ("EIF-1", "identifier")
			o.put_string ("Compile feature", "title")
			o.put_string ("Todo", "state")
			o.put_boolean (True, "dispatchable")
			create labels.make_empty
			labels.extend (create {JSON_STRING}.make_from_string (" Compiler "))
			o.put (labels, "labels")
			create codec.make
			codec.decode (o)
			assert ("decoded", attached codec.issue)
			if attached codec.issue as issue then
				assert ("label normalized", issue.labels.count = 1 and then issue.labels.first.same_string ("compiler"))
				create tracker.make
				tracker.put (issue)
				create states.make (1)
				states.extend (" todo ")
				tracker.fetch_issues_by_states (states)
				assert ("state fetch", tracker.last_issues.count = 1)
				create ids.make (0)
				tracker.fetch_issues_by_ids (ids)
				assert ("empty ids short circuit", tracker.last_issues.is_empty)
			end
		end

	test_secret_native_ref_normalizes_to_null
		local
			o, native: JSON_OBJECT
			codec: SYM_ISSUE_CODEC
		do
			create o.make_empty
			o.put_string ("opaque-secret", "id")
			o.put_string ("EIF-SECRET", "identifier")
			o.put_string ("Do not expose secrets", "title")
			o.put_string ("Todo", "state")
			o.put_boolean (True, "dispatchable")
			create native.make_empty
			native.put_string ("must-not-enter-prompt", "proxy_authorization")
			native.put_string ("must-not-enter-prompt", "set_cookie")
			o.put (native, "native_ref")
			create codec.make
			codec.decode (o)
			assert ("decoded", attached codec.issue)
			assert ("secret native ref removed", attached codec.issue as issue and then issue.native_ref = Void)
		end

	test_json_tracker_rejects_duplicate_identity
		local
			root, tracker_object, provider: JSON_OBJECT
			workflow: SYM_WORKFLOW
			config: SYM_CONFIG
			tracker: SYM_JSON_FILE_TRACKER
			path: PATH
			states: ARRAYED_LIST [STRING_32]
		do
			create root.make_empty
			create tracker_object.make_empty
			tracker_object.put_string ("json_file", "kind")
			create provider.make_empty
			provider.put_string ("tests/fixtures/duplicate_issues.json", "path")
			tracker_object.put (provider, "provider")
			tracker_object.put (json.string_array (<<"Todo">>), "active_states")
			tracker_object.put (json.string_array (<<"Done">>), "terminal_states")
			root.put (tracker_object, "tracker")
			create path.make_from_string ("WORKFLOW.md")
			create workflow.make (root, "prompt", path.absolute_path, "duplicate-tracker")
			create config.make (workflow)
			assert ("config valid", config.is_valid)
			create tracker.make
			tracker.validate_config (config)
			assert ("tracker config valid", tracker.last_error = Void)
			create states.make (1)
			states.extend ("Todo")
			tracker.fetch_issues_by_states (states)
			assert ("duplicate rejected", attached tracker.last_error as e and then e.code.same_string ("tracker_response"))
			assert ("atomic empty result", tracker.last_issues.is_empty)
		end

	test_rfc3339_offsets
		local
			p: SYM_RFC3339
			a, b: detachable DATE_TIME
		do
			create p
			a := p.parsed ("2026-08-15T12:30:10.250Z")
			b := p.parsed ("2026-08-15T14:30:10.250+02:00")
			assert ("valid timestamps", a /= Void and b /= Void)
			if attached a as av and attached b as bv then assert ("same instant", av.is_equal (bv)) end
			assert ("invalid timestamp", p.parsed ("not-a-time") = Void)
		end

feature -- Scheduling policy tests

	test_label_routing_uses_value_comparison
		local
			issue: SYM_ISSUE
			labels, required: ARRAYED_LIST [STRING_32]
			strings: SYM_STRINGS
		do
			create issue.make ("opaque", "EIFFEL-1", "Route labels", "Todo")
			create strings
			assert ("normalized copy", strings.normalized (issue.identifier).same_string ("eiffel-1"))
			assert ("identifier spelling preserved", issue.identifier.same_string ("EIFFEL-1"))
			assert ("state comparison copy", issue.normalized_state.same_string ("todo") and then issue.state.same_string ("Todo"))
			create labels.make (1)
			labels.extend (" Symphony ")
			issue.set_labels (labels)
			create required.make (1)
			required.extend ("symphony")
			assert ("equal label values route", strings.has_all_labels (issue.labels, required))
			required.extend ("backend")
			assert ("missing label blocks", not strings.has_all_labels (issue.labels, required))
		end

	test_retry_backoff_and_dispatch_order
		local
			policy: SYM_DISPATCH_POLICY
			first, second, invalid: SYM_ISSUE
			priority: INTEGER_64_REF
			issues, ordered: ARRAYED_LIST [SYM_ISSUE]
		do
			create policy
			assert ("attempt one", policy.failure_delay_ms (1, 300_000) = 10_000)
			assert ("attempt two", policy.failure_delay_ms (2, 300_000) = 20_000)
			assert ("cap", policy.failure_delay_ms (6, 300_000) = 300_000)
			assert ("small cap", policy.failure_delay_ms (1, 5_000) = 5_000)
			create first.make ("1", "EIFFEL-1", "First", "Todo")
			create priority
			priority.set_item (1)
			first.set_priority (priority)
			create second.make ("2", "EIFFEL-2", "Second", "Todo")
			priority.set_item (2)
			second.set_priority (priority)
			create invalid.make ("3", "EIFFEL-0", "Default bucket", "Todo")
			priority.set_item (0)
			invalid.set_priority (priority)
			create issues.make (3)
			issues.extend (invalid)
			issues.extend (second)
			issues.extend (first)
			ordered := policy.sorted_for_dispatch (issues)
			assert ("priority order", ordered.count = 3 and then ordered [1] = first and then ordered [2] = second and then ordered [3] = invalid)
		end

	test_clock_rfc3339_shape
		local
			clock: SYM_CLOCK
			stamp: STRING_8
			before, after: INTEGER_64
		do
			create clock
			stamp := clock.iso_8601_now
			assert ("timestamp shape", stamp.count = 24 and then stamp [5] = '-' and then stamp [11] = 'T' and then stamp [24] = 'Z')
			before := clock.monotonic_milliseconds
			execution_environment.sleep (1_000_000)
			after := clock.monotonic_milliseconds
			assert ("monotonic nondecreasing", after >= before)
		end

feature {NONE} -- Fixtures

	base_memory_config: JSON_OBJECT
		local
			tracker: JSON_OBJECT
		do
			create Result.make_empty
			create tracker.make_empty
			tracker.put_string ("memory", "kind")
			tracker.put (json.string_array (<<"Todo">>), "active_states")
			tracker.put (json.string_array (<<"Done">>), "terminal_states")
			Result.put (tracker, "tracker")
		end

	json: SYM_JSON
		once
			create Result
		end

	execution_environment: EXECUTION_ENVIRONMENT
		once
			create Result
		end

end
