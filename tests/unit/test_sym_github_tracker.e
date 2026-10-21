note
	description: "GitHub snapshot, process-boundary, configuration, and refresh lifecycle tests."
	testing: "execution/serial/symphony"

class
	TEST_SYM_GITHUB_TRACKER

inherit
	EQA_TEST_SET

feature -- Configuration lifecycle

	test_configuration_invalidates_previous_source
		local
			runner: SYM_FAKE_SHELL_RUNNER
			tracker: SYM_GITHUB_TRACKER
			p: JSON_OBJECT
		do
			create runner.make
			create tracker.make_with_runner (runner)
			tracker.fetch_issues_by_states (strings (<<"open">>))
			assert ("unconfigured read fails without launching", tracker.last_error /= Void and runner.call_count = 0)
			tracker.validate_config (config (provider ("Old/Repo"), "open", "closed"))
			assert ("valid config", tracker.last_error = Void)
			runner.enqueue_success (snapshot (<<page (<<record (101, 1, "open")>>)>>))
			tracker.fetch_issues_by_states (strings (<<"open">>))
			assert ("old source read", tracker.last_issues.count = 1)
			tracker.validate_config (config (provider ("not-a-repository"), "open", "closed"))
			assert ("invalid revalidation clears result", tracker.last_error /= Void and tracker.last_issues.is_empty)
			tracker.fetch_issues_by_states (strings (<<"open">>))
			assert ("invalid source cannot fall back", tracker.last_error /= Void and tracker.last_issues.is_empty and runner.call_count = 1)
			tracker.fetch_issues_by_ids (strings (<<"github:github.com:101">>))
			assert ("invalid source also blocks id refresh", tracker.last_error /= Void and runner.call_count = 1)
			p := provider ("New/Repo")
			p.put_string ("GitHub.Example.Com", "hostname")
			tracker.validate_config (config (p, "open", "closed"))
			runner.enqueue_success (snapshot (<<page (<<record (202, 2, "open")>>)>>))
			tracker.fetch_issues_by_states (strings (<<"open">>))
			assert ("revalidated source recovers", tracker.last_error = Void and tracker.last_issues.count = 1 and runner.call_count = 2)
			assert ("new source identity", tracker.last_issues.first.identifier.same_string ("github.example.com/new/repo#2"))
		end

	test_configuration_boundaries
		local
			runner: SYM_FAKE_SHELL_RUNNER
			tracker: SYM_GITHUB_TRACKER
			p: JSON_OBJECT
		do
			create runner.make
			create tracker.make_with_runner (runner)
			across <<"", "owner", "owner/repo/extra", "/repo", "owner/", "owner/repo?x=1", "owner/repo#1", "../repo">> as invalid_repo loop
				tracker.validate_config (config (provider (invalid_repo.item), "open", "closed"))
				assert ("unsafe repository rejected", tracker.last_error /= Void)
			end
			across <<"", "https://github.com", "github.com/path", "github.com?x=1", "-github.com">> as invalid_host loop
				p := provider ("Owner/Repo")
				p.put_string (invalid_host.item, "hostname")
				tracker.validate_config (config (p, "open", "closed"))
				assert ("unsafe hostname rejected", tracker.last_error /= Void)
			end
			across <<{INTEGER_64} 0, {INTEGER_64} -1, {INTEGER_64} 2_147_483_648>> as invalid_timeout loop
				p := provider ("Owner/Repo")
				p.put_integer (invalid_timeout.item, "request_timeout_ms")
				tracker.validate_config (config (p, "open", "closed"))
				assert ("timeout outside process range rejected", tracker.last_error /= Void)
			end
			p := provider ("Owner/Repo")
			p.put_string ("30000", "request_timeout_ms")
			tracker.validate_config (config (p, "open", "closed"))
			assert ("string timeout rejected", tracker.last_error /= Void)
			p.replace (create {JSON_NUMBER}.make_real (0.5), "request_timeout_ms")
			tracker.validate_config (config (p, "open", "closed"))
			assert ("fractional timeout rejected", tracker.last_error /= Void)
			tracker.validate_config (config (provider ("Owner/Repo"), "Todo", "closed"))
			assert ("unsupported active state rejected", tracker.last_error /= Void)
			tracker.validate_config (config (provider ("Owner/Repo"), "open", "Done"))
			assert ("unsupported terminal state rejected", tracker.last_error /= Void)
			tracker.fetch_issues_by_states (strings (<<"open">>))
			assert ("all invalid configs avoid process launch", tracker.last_error /= Void and runner.call_count = 0)
			p := provider ("Owner/Repo")
			p.put_integer (2_147_483_647, "request_timeout_ms")
			tracker.validate_config (config (p, " OPEN ", "CLOSED"))
			assert ("process max and normalized states accepted", tracker.last_error = Void)
		end

feature -- Snapshot lifecycle

	test_paginated_snapshot_and_process_arguments
		local
			runner: SYM_FAKE_SHELL_RUNNER
			tracker: SYM_GITHUB_TRACKER
			p, pull_request: JSON_OBJECT
			c: SYM_CONFIG
		do
			create runner.make
			create tracker.make_with_runner (runner)
			p := provider ("Owner/Repo")
			p.put_string ("GitHub.Example.Com", "hostname")
			p.put_integer (12_345, "request_timeout_ms")
			c := config (p, "open", "closed")
			tracker.validate_config (c)
			create pull_request.make_empty
			pull_request.put (create {JSON_OBJECT}.make_empty, "pull_request")
			runner.enqueue_success (snapshot (<<page (<<record (101, 1, "open"), pull_request>>), page (<<record (102, 2, "closed"), record (103, 3, "open")>>)>>))
			tracker.fetch_issues_by_states (strings (<<" OPEN ">>))
			assert ("all pages included and PR ignored", tracker.last_error = Void and tracker.last_issues.count = 2)
			assert ("first identity", tracker.last_issues.first.id.same_string ("github:github.example.com:101") and tracker.last_issues.first.identifier.same_string ("github.example.com/owner/repo#1"))
			assert ("later page retained", tracker.last_issues.last.id.same_string ("github:github.example.com:103"))
			assert ("one CLI invocation", runner.call_count = 1 and runner.pending_count = 0)
			assert ("executable and workflow cwd", runner.executable.same_string ("gh") and runner.cwd.is_equal (c.workflow_path.parent))
			assert ("configured timeout", runner.timeouts.first = 12_345)
			assert ("API command", has_argument (runner.arguments, "api") and has_argument (runner.arguments, "--method") and has_argument (runner.arguments, "GET"))
			assert ("hostname is explicit", has_argument (runner.arguments, "--hostname") and has_argument (runner.arguments, "github.example.com"))
			assert ("pagination and pinned API", has_argument (runner.arguments, "--paginate") and has_argument (runner.arguments, "--slurp") and has_argument (runner.arguments, "Accept: application/vnd.github+json") and has_argument (runner.arguments, "X-GitHub-Api-Version: 2022-11-28"))
			assert ("deterministic all-state endpoint", has_argument (runner.arguments, "/repos/owner/repo/issues?state=all&per_page=100&sort=created&direction=asc"))
		end

	test_refresh_failure_empty_recovery_and_missing_issue
		local
			runner: SYM_FAKE_SHELL_RUNNER
			tracker: SYM_GITHUB_TRACKER
			changed: JSON_OBJECT
			ids: ARRAYED_LIST [STRING_32]
		do
			create runner.make
			create tracker.make_with_runner (runner)
			tracker.validate_config (config (provider ("Owner/Repo"), "open", "closed"))
			ids := strings (<<"github:github.com:101">>)
			runner.enqueue_success (snapshot (<<page (<<record (101, 1, "open")>>)>>))
			tracker.fetch_issues_by_ids (ids)
			assert ("id refresh works before first poll", tracker.last_error = Void and tracker.last_issues.count = 1 and runner.call_count = 1)
			assert ("default timeout", runner.timeouts.first = 30_000)
			runner.enqueue (create {SYM_PROCESS_RESULT}.make (True, False, 1, "", "request failed"))
			tracker.fetch_issues_by_ids (ids)
			assert ("failed refresh removes old result", tracker.last_error /= Void and tracker.last_issues.is_empty)
			tracker.fetch_issues_by_ids (create {ARRAYED_LIST [STRING_32]}.make (0))
			assert ("empty after failure does not consume response", tracker.last_issues.is_empty and runner.call_count = 2)
			changed := record (101, 1, "closed")
			changed.put (json.string_array (<<" Ready ">>), "labels")
			runner.enqueue_success (snapshot (<<page (<<changed>>)>>))
			tracker.fetch_issues_by_ids (ids)
			assert ("fresh changed state and labels", tracker.last_error = Void and tracker.last_issues.count = 1 and then tracker.last_issues.first.state.same_string ("closed") and then tracker.last_issues.first.labels.has ("ready"))
			runner.enqueue_success (snapshot (<<page (<<changed>>), page (<<changed>>)>>))
			tracker.fetch_issues_by_ids (ids)
			assert ("later duplicate invalidates whole snapshot", tracker.last_error /= Void and tracker.last_issues.is_empty)
			runner.enqueue_success (snapshot (<<page (<<record (101, 1, "open")>>)>>))
			tracker.fetch_issues_by_states (strings (<<"open">>))
			assert ("poll recovers after duplicate", tracker.last_error = Void and tracker.last_issues.count = 1)
			runner.enqueue_success (snapshot (<<page (<<record (202, 2, "open")>>)>>))
			tracker.fetch_issues_by_ids (ids)
			assert ("missing issue has no stale cached fallback", tracker.last_error = Void and tracker.last_issues.is_empty and runner.call_count = 6)
		end

	test_transport_and_payload_failures_are_atomic
		local
			runner: SYM_FAKE_SHELL_RUNNER
			tracker: SYM_GITHUB_TRACKER
			good, malformed: JSON_OBJECT
			states: ARRAYED_LIST [STRING_32]
			payload: STRING_8
		do
			create runner.make
			create tracker.make_with_runner (runner)
			tracker.validate_config (config (provider ("Owner/Repo"), "open", "closed"))
			states := strings (<<"open">>)
			good := record (101, 1, "open")
			payload := snapshot (<<page (<<good>>)>>)
			runner.enqueue (create {SYM_PROCESS_RESULT}.make (True, False, 1, payload, "secret CLI detail"))
			runner.enqueue (create {SYM_PROCESS_RESULT}.make (True, True, 0, payload, "timeout"))
			runner.enqueue (create {SYM_PROCESS_RESULT}.make (False, False, -1, payload, "launch failure"))
			runner.enqueue_truncated_success (payload)
			across 1 |..| 4 as attempt loop
				tracker.fetch_issues_by_states (states)
				assert ("process failure cannot publish valid partial output", tracker.last_error /= Void and tracker.last_issues.is_empty)
				assert ("public error omits captured CLI data", attached tracker.last_error as failure and then not failure.message.has_substring ("secret CLI detail") and then not failure.message.has_substring ("A GitHub task"))
			end
			across <<"not JSON", "{}", "[]", "[{}]", "[[1]]", "[[{}]]">> as bad_payload loop
				runner.enqueue_success (bad_payload.item)
				tracker.fetch_issues_by_states (states)
				assert ("malformed envelope or record fails", tracker.last_error /= Void and tracker.last_issues.is_empty)
			end
			malformed := record (202, 2, "closed")
			malformed.replace_with_string ("", "title")
			runner.enqueue_success (snapshot (<<page (<<good>>), page (<<malformed>>)>>))
			tracker.fetch_issues_by_states (states)
			assert ("malformed filtered-out issue invalidates preceding result", tracker.last_error /= Void and tracker.last_issues.is_empty)
			runner.enqueue_success (snapshot (<<page (<<good>>), page (<<record (101, 2, "closed")>>)>>))
			tracker.fetch_issues_by_states (states)
			assert ("duplicate id across states and pages rejected", tracker.last_error /= Void and tracker.last_issues.is_empty)
			runner.enqueue_success (snapshot (<<page (<<good>>), page (<<record (202, 1, "closed")>>)>>))
			tracker.fetch_issues_by_states (states)
			assert ("duplicate identifier across pages rejected", tracker.last_error /= Void and tracker.last_issues.is_empty)
			runner.enqueue_success ("[[],[]]")
			tracker.fetch_issues_by_states (states)
			assert ("empty successful snapshot recovers", tracker.last_error = Void and tracker.last_issues.is_empty and runner.pending_count = 0)
		end

	test_empty_reads_and_secret_environment_names
		local
			runner: SYM_FAKE_SHELL_RUNNER
			tracker: SYM_GITHUB_TRACKER
			names: ARRAYED_LIST [STRING_32]
		do
			create runner.make
			create tracker.make_with_runner (runner)
			tracker.fetch_issues_by_states (create {ARRAYED_LIST [STRING_32]}.make (0))
			tracker.fetch_issues_by_ids (create {ARRAYED_LIST [STRING_32]}.make (0))
			assert ("empty unconfigured reads skip process", tracker.last_issues.is_empty and runner.call_count = 0)
			tracker.validate_config (config (provider ("Owner/Repo"), "open", "closed"))
			runner.enqueue_success (snapshot (<<page (<<record (101, 1, "open")>>)>>))
			tracker.fetch_issues_by_states (strings (<<"open">>))
			assert ("preceding result exists", tracker.last_issues.count = 1)
			tracker.fetch_issues_by_states (create {ARRAYED_LIST [STRING_32]}.make (0))
			tracker.fetch_issues_by_ids (create {ARRAYED_LIST [STRING_32]}.make (0))
			assert ("empty reads clear preceding result and skip process", tracker.last_issues.is_empty and runner.call_count = 1)
			names := tracker.secret_environment_names
			assert ("four authentication environment variables", names.count = 4)
			assert ("standard token names", has_argument (names, "GH_TOKEN") and has_argument (names, "GITHUB_TOKEN"))
			assert ("enterprise token names", has_argument (names, "GH_ENTERPRISE_TOKEN") and has_argument (names, "GITHUB_ENTERPRISE_TOKEN"))
		end

feature -- Codec boundaries

	test_codec_mapping_native_reference_and_pull_request_reset
		local
			codec: SYM_GITHUB_ISSUE_CODEC
			o, assignee, label, supplied_native, pr: JSON_OBJECT
			labels: JSON_ARRAY
		do
			create codec.make
			o := record (9_007_199_254_740_993, 42, "open")
			o.put_string ("Detailed body", "body")
			o.put_string ("https://github.example.com/owner/repo/issues/42", "html_url")
			o.put_string ("2026-08-15T12:30:10Z", "created_at")
			o.put_string ("2026-08-15T14:30:10+02:00", "updated_at")
			create assignee.make_empty
			assignee.put_integer (123, "id")
			o.put (assignee, "assignee")
			create labels.make_empty
			labels.extend (create {JSON_STRING}.make_from_string (" Compiler "))
			create label.make_empty
			label.put_string (" READY ", "name")
			labels.extend (label)
			o.put (labels, "labels")
			create supplied_native.make_empty
			supplied_native.put_string ("must-not-enter-prompt", "token")
			o.put (supplied_native, "native_ref")
			o.put_string ("must-not-enter-prompt", "authorization")
			codec.decode (o, "owner/repo", "github.example.com")
			assert ("large integer identity decoded exactly", codec.error = Void and not codec.is_pull_request and attached codec.issue)
			if attached codec.issue as issue then
				assert ("provider identity", issue.id.same_string ("github:github.example.com:9007199254740993") and issue.identifier.same_string ("github.example.com/owner/repo#42"))
				assert ("body and URL mapped", attached issue.description as body and then body.same_string ("Detailed body") and then attached issue.url as url and then url.same_string ("https://github.example.com/owner/repo/issues/42"))
				assert ("assignee and labels mapped", attached issue.assignee_id as assignee_id and then assignee_id.same_string ("123") and then issue.labels.count = 2 and then issue.labels.has ("compiler") and then issue.labels.has ("ready"))
				assert ("dates mapped as equivalent instants", attached issue.created_at as created and then attached issue.updated_at as updated and then created.is_equal (updated))
				assert ("default dispatch behavior", issue.dispatchable and issue.priority = Void and issue.branch_name = Void and issue.blocked_by.is_empty)
				assert ("native reference is allowlisted", attached issue.native_ref as native and then native.count = 3 and then attached json.string (native, "hostname") as host and then host.same_string ("github.example.com") and then attached json.string (native, "repository") as repo and then repo.same_string ("owner/repo") and then attached json.integer_64 (native, "number") as number and then number.item = 42)
			end
			create pr.make_empty
			pr.put (create {JSON_OBJECT}.make_empty, "pull_request")
			codec.decode (pr, "owner/repo", "github.example.com")
			assert ("PR does not retain prior issue", codec.is_pull_request and codec.issue = Void and codec.error = Void)
			codec.decode (record (101, 1, "closed"), "owner/repo", "github.example.com")
			assert ("ordinary issue resets PR and optional state", not codec.is_pull_request and codec.error = Void and then attached codec.issue as next_issue and then next_issue.description = Void and then next_issue.url = Void and then next_issue.assignee_id = Void and then next_issue.labels.is_empty and then next_issue.created_at = Void and then next_issue.updated_at = Void)
		end

	test_codec_rejects_malformed_required_fields_and_recovers
		local
			codec: SYM_GITHUB_ISSUE_CODEC
			o: JSON_OBJECT
		do
			create codec.make
			across <<{INTEGER_64} 0, {INTEGER_64} -1>> as invalid_id loop
				codec.decode (record (invalid_id.item, 1, "open"), "owner/repo", "github.com")
				assert ("nonpositive id rejected", codec.error /= Void and codec.issue = Void)
				codec.decode (record (101, invalid_id.item, "open"), "owner/repo", "github.com")
				assert ("nonpositive issue number rejected", codec.error /= Void and codec.issue = Void)
			end
			o := record (101, 1, "open")
			o.replace_with_string ("101", "id")
			codec.decode (o, "owner/repo", "github.com")
			assert ("string id rejected", codec.error /= Void and codec.issue = Void)
			o := record (101, 1, "open")
			o.replace (create {JSON_NUMBER}.make_real (1.5), "number")
			codec.decode (o, "owner/repo", "github.com")
			assert ("fractional number rejected", codec.error /= Void and codec.issue = Void)
			o := record (101, 1, "open")
			o.replace (create {JSON_NUMBER}.make_natural (9_223_372_036_854_775_808), "id")
			codec.decode (o, "owner/repo", "github.com")
			assert ("overflow id rejected", codec.error /= Void and codec.issue = Void)
			o := record (101, 1, "open")
			o.replace_with_string (" %T ", "title")
			codec.decode (o, "owner/repo", "github.com")
			assert ("blank title rejected", codec.error /= Void and codec.issue = Void)
			codec.decode (record (101, 1, "Todo"), "owner/repo", "github.com")
			assert ("unknown GitHub state rejected", codec.error /= Void and codec.issue = Void)
			codec.decode (record (101, 1, "open"), "owner/repo", "github.com")
			assert ("valid decode clears preceding error", codec.error = Void and attached codec.issue and not codec.is_pull_request)
			o := record (101, 1, "closed")
			o.put (Void, "body")
			o.put (Void, "assignee")
			o.put (Void, "created_at")
			o.put (Void, "updated_at")
			codec.decode (o, "owner/repo", "github.com")
			assert ("nullable optional fields accepted", codec.error = Void and then attached codec.issue as issue and then issue.description = Void and then issue.assignee_id = Void and then issue.created_at = Void and then issue.updated_at = Void)
			o.replace_with_integer (42, "body")
			o.put_boolean (True, "html_url")
			o.replace_with_string ("wrong shape", "assignee")
			o.replace_with_string ("invalid timestamp", "created_at")
			o.replace_with_boolean (False, "updated_at")
			o.put_integer (42, "labels")
			codec.decode (o, "owner/repo", "github.com")
			assert ("malformed optionals do not invalidate core issue", codec.error = Void and then attached codec.issue as optional_issue and then optional_issue.description = Void and then optional_issue.url = Void and then optional_issue.assignee_id = Void and then optional_issue.created_at = Void and then optional_issue.updated_at = Void and then optional_issue.labels.is_empty)
		end

feature {NONE} -- Fixtures

	provider (a_repository: READABLE_STRING_GENERAL): JSON_OBJECT
		do
			create Result.make_empty
			Result.put_string (a_repository, "repository")
		end

	config (a_provider: JSON_OBJECT; a_active, a_terminal: READABLE_STRING_GENERAL): SYM_CONFIG
		local
			root, tracker: JSON_OBJECT
			workflow: SYM_WORKFLOW
			path: PATH
		do
			create root.make_empty
			create tracker.make_empty
			tracker.put_string ("github", "kind")
			tracker.put (a_provider, "provider")
			tracker.put (json.string_array (<<a_active>>), "active_states")
			tracker.put (json.string_array (<<a_terminal>>), "terminal_states")
			root.put (tracker, "tracker")
			create path.make_from_string ("tests/fixtures/github/WORKFLOW.md")
			create workflow.make (root, "prompt", path.absolute_path, "github-test")
			create Result.make (workflow)
		end

	record (a_id, a_number: INTEGER_64; a_state: READABLE_STRING_GENERAL): JSON_OBJECT
		do
			create Result.make_empty
			Result.put_integer (a_id, "id")
			Result.put_integer (a_number, "number")
			Result.put_string ("A GitHub task", "title")
			Result.put_string (a_state, "state")
		end

	page (a_records: ARRAY [JSON_OBJECT]): JSON_ARRAY
		do
			create Result.make_empty
			across a_records as c loop Result.extend (c.item) end
		end

	snapshot (a_pages: ARRAY [JSON_ARRAY]): STRING_8
		local
			root: JSON_ARRAY
		do
			create root.make_empty
			across a_pages as c loop root.extend (c.item) end
			Result := root.representation
		end

	strings (a_values: ARRAY [STRING_32]): ARRAYED_LIST [STRING_32]
		do
			create Result.make (a_values.count)
			Result.compare_objects
			across a_values as c loop Result.extend (c.item) end
		end

	has_argument (a_arguments: ITERABLE [STRING_32]; a_value: READABLE_STRING_GENERAL): BOOLEAN
		do
			across a_arguments as c until Result loop Result := c.item.same_string_general (a_value) end
		end

	json: SYM_JSON once create Result end

end
