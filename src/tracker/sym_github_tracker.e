note
	description: "Read-only GitHub Issues tracker using the authenticated GitHub CLI."

class
	SYM_GITHUB_TRACKER

inherit
	SYM_TRACKER_ADAPTER
		redefine
			secret_environment_names
		end

create
	make,
	make_with_runner

feature {NONE} -- Initialization

	make
		local
			request_runner: SYM_SHELL_RUNNER
		do
			create request_runner.make_with_output_limit (16_777_216)
			make_with_runner (request_runner)
		end

	make_with_runner (a_runner: SYM_SHELL_RUNNER)
		do
			runner := a_runner
			create repository.make_empty
			hostname := "github.com"
			request_timeout_ms := 30_000
			create request_directory.make_empty
			create last_issues.make (0)
			create codec.make
		end

feature -- Access

	kind: STRING_32 = "github"

	repository: STRING_32

	hostname: STRING_32

	request_timeout_ms: INTEGER_64

	last_issues: ARRAYED_LIST [SYM_ISSUE]

	last_error: detachable SYM_ERROR

	secret_environment_names: ARRAYED_LIST [STRING_32]
		do
			create Result.make (4)
			Result.extend ("GH_TOKEN")
			Result.extend ("GITHUB_TOKEN")
			Result.extend ("GH_ENTERPRISE_TOKEN")
			Result.extend ("GITHUB_ENTERPRISE_TOKEN")
		end

feature -- Configuration

	validate_config (a_config: SYM_CONFIG)
			-- Local validation only: never invoke gh or contact GitHub here.
		local
			provider: JSON_OBJECT
		do
			-- Revalidation invalidates the old source even when the new config fails.
			is_configured := False
			last_error := Void
			last_issues.wipe_out
			create repository.make_empty
			hostname := "github.com"
			request_timeout_ms := 30_000
			create request_directory.make_empty
			provider := a_config.tracker_provider
			if not a_config.tracker_kind.is_case_insensitive_equal (kind) then
				create last_error.make ("unsupported_tracker_kind", "Expected tracker.kind=github")
			elseif not attached json.string (provider, "repository") as repo or else
				not is_repository (strings.trimmed (repo))
			then
				invalid_config ("GitHub provider.repository must be owner/repo")
			else
				repository := strings.normalized (repo)
				if provider.has_key ("hostname") then
					if attached json.string (provider, "hostname") as host and then is_hostname (strings.trimmed (host)) then
						hostname := strings.normalized (host)
					else
						invalid_config ("GitHub provider.hostname must be a DNS hostname without scheme, port, or path")
					end
				end
				if provider.has_key ("request_timeout_ms") then
					if attached json.integer_64 (provider, "request_timeout_ms") as timeout and then
						timeout.item > 0 and then timeout.item <= {INTEGER}.max_value
					then
						request_timeout_ms := timeout.item
					else
						invalid_config ("GitHub provider.request_timeout_ms must be an integer from 1 through 2147483647")
					end
				end
				if not supported_states (a_config.active_states) or else not supported_states (a_config.terminal_states) then
					invalid_config ("GitHub tracker states must use open or closed")
				end
				if last_error = Void then
					request_directory := a_config.workflow_path.parent
					is_configured := True
				end
			end
		ensure then
			configured_on_success: last_error = Void implies is_configured
			no_stale_issues: last_issues.is_empty
		end

feature -- Reads

	fetch_issues_by_states (a_states: LIST [STRING_32])
		do
			create last_issues.make (10)
			last_error := Void
			if not a_states.is_empty then read_and_filter (a_states, Void) end
		end

	fetch_issues_by_ids (a_ids: LIST [STRING_32])
			-- Read all states without a mutable ID-to-number cache. Fresh adapters
			-- can refresh previously dispatched IDs after workflow replacement.
		do
			create last_issues.make (a_ids.count)
			last_error := Void
			if not a_ids.is_empty then read_and_filter (Void, a_ids) end
		end

feature {NONE} -- Requests and atomic snapshots

	read_and_filter (a_states, a_ids: detachable LIST [STRING_32])
		local
			failed: BOOLEAN
		do
			if failed then
				last_issues.wipe_out
				create last_error.make ("tracker_request", "Unexpected GitHub request failure")
			elseif not is_configured then
				invalid_config ("GitHub tracker must be validated before reading")
			else
				runner.run ("gh", request_arguments, request_directory, request_timeout_ms)
				if runner.last_result.timed_out then
					create last_error.make ("tracker_request", "GitHub request exceeded provider.request_timeout_ms")
				elseif not runner.last_result.is_success then
					-- CLI output can include credentials or raw provider payloads. Do not
					-- place stdout, stderr, or command text in public errors.
					create last_error.make ("tracker_request", "GitHub request failed; check gh installation, authentication, repository access, and rate limits")
				elseif runner.last_output_truncated then
					response_error ("GitHub snapshot exceeds the 16 MiB capture limit")
				else
					decode_snapshot (runner.last_result.output, a_states, a_ids)
				end
			end
			if last_error /= Void then last_issues.wipe_out end
		rescue
			failed := True
			retry
		end

	request_arguments: ARRAYED_LIST [READABLE_STRING_GENERAL]
		do
			create Result.make (13)
			Result.extend ("api")
			Result.extend ("--method")
			Result.extend ("GET")
			Result.extend ("--hostname")
			Result.extend (hostname)
			Result.extend ("--paginate")
			Result.extend ("--slurp")
			Result.extend ("/repos/" + repository + "/issues?state=all&per_page=100&sort=created&direction=asc")
			Result.extend ("--header")
			Result.extend ("Accept: application/vnd.github+json")
			Result.extend ("--header")
			Result.extend ("X-GitHub-Api-Version: 2022-11-28")
		end

	decode_snapshot (a_text: READABLE_STRING_8; a_states, a_ids: detachable LIST [STRING_32])
		local
			seen_ids, seen_identifiers, seen_keys: HASH_TABLE [BOOLEAN, STRING_32]
			identifier_key, workspace_key: STRING_32
		do
			if attached {JSON_ARRAY} json.parsed_value (a_text) as pages and then not pages.is_empty then
				create seen_ids.make (100)
				create seen_identifiers.make (100)
				create seen_keys.make (100)
				seen_ids.compare_objects
				seen_identifiers.compare_objects
				seen_keys.compare_objects
				across pages as page_cursor until last_error /= Void loop
					if attached {JSON_ARRAY} page_cursor.item as records then
						across records as record_cursor until last_error /= Void loop
							if attached {JSON_OBJECT} record_cursor.item as record then
								codec.decode (record, repository, hostname)
								if attached codec.issue as issue then
									identifier_key := filesystem_key (issue.identifier)
									workspace_key := filesystem_key (safety.workspace_key (issue.identifier))
									if seen_ids.has (issue.id) or else seen_identifiers.has (identifier_key) or else seen_keys.has (workspace_key) then
										response_error ("GitHub snapshot contains duplicate issue or workspace identities")
									else
										seen_ids.force (True, issue.id)
										seen_identifiers.force (True, identifier_key)
										seen_keys.force (True, workspace_key)
										if (attached a_states as states and then normalized_has (states, issue.state)) or else
											(attached a_ids as ids and then exact_has (ids, issue.id))
										then
											last_issues.extend (issue)
										end
									end
								elseif attached codec.error as decode_error then
									last_error := decode_error
								end
							else
								response_error ("Every GitHub issue record must be an object")
							end
						end
					else
						response_error ("Every GitHub response page must be an array")
					end
				end
			else
				response_error ("GitHub response must be a nonempty array of issue pages")
			end
		end

feature {NONE} -- Validation and filtering

	is_repository (a_value: STRING_32): BOOLEAN
		local
			parts: LIST [STRING_32]
		do
			parts := a_value.split ('/')
			Result := parts.count = 2 and then is_repository_component (parts.first) and then
				is_repository_component (parts.last)
		end

	is_repository_component (a_value: STRING_32): BOOLEAN
		do
			Result := not a_value.is_empty and then not a_value.same_string (".") and then not a_value.same_string ("..") and then
				across a_value as cursor all
					is_ascii_alphanumeric (cursor.item) or else cursor.item = '-' or else cursor.item = '_' or else cursor.item = '.'
				end
		end

	is_hostname (a_value: STRING_32): BOOLEAN
		local
			parts: LIST [STRING_32]
		do
			parts := a_value.split ('.')
			Result := not a_value.is_empty and then a_value.count <= 253
			across parts as cursor until not Result loop
				Result := not cursor.item.is_empty and then cursor.item.count <= 63 and then
					is_ascii_alphanumeric (cursor.item [1]) and then
					is_ascii_alphanumeric (cursor.item [cursor.item.count]) and then
					across cursor.item as character_cursor all
						is_ascii_alphanumeric (character_cursor.item) or else character_cursor.item = '-'
					end
			end
		end

	is_ascii_alphanumeric (a_character: CHARACTER_32): BOOLEAN
		do
			Result := (a_character >= 'a' and a_character <= 'z') or else
				(a_character >= 'A' and a_character <= 'Z') or else (a_character >= '0' and a_character <= '9')
		end

	supported_states (a_states: LIST [STRING_32]): BOOLEAN
		local
			state: STRING_32
		do
			Result := not a_states.is_empty
			across a_states as cursor until not Result loop
				state := strings.normalized (cursor.item)
				Result := state.same_string ("open") or else state.same_string ("closed")
			end
		end

	normalized_has (a_values: LIST [STRING_32]; a_value: READABLE_STRING_GENERAL): BOOLEAN
		local
			value: STRING_32
		do
			value := strings.normalized (a_value)
			across a_values as cursor until Result loop Result := strings.normalized (cursor.item).same_string (value) end
		end

	exact_has (a_values: LIST [STRING_32]; a_value: STRING_32): BOOLEAN
		do
			across a_values as cursor until Result loop Result := cursor.item.same_string (a_value) end
		end

	filesystem_key (a_value: STRING_32): STRING_32
		do
			Result := a_value.twin
			if {PLATFORM}.is_windows or else {PLATFORM}.is_mac then Result.to_lower end
		end

	invalid_config (a_message: READABLE_STRING_GENERAL)
		do
			if last_error = Void then create last_error.make ("invalid_tracker_config", a_message) end
		end

	response_error (a_message: READABLE_STRING_GENERAL)
		do
			create last_error.make ("tracker_response", a_message)
		end

feature {NONE} -- Storage

	is_configured: BOOLEAN

	request_directory: PATH

	runner: SYM_SHELL_RUNNER

	codec: SYM_GITHUB_ISSUE_CODEC

	json: SYM_JSON once create Result end

	strings: SYM_STRINGS once create Result end

	safety: SYM_PATH_SAFETY once create Result end

end
