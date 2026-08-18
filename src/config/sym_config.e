note
	description: "Validated typed view over WORKFLOW.md front matter."

class
	SYM_CONFIG

create
	make

feature {NONE} -- Initialization

	make (a_workflow: SYM_WORKFLOW)
		do
			workflow_path := a_workflow.path
			create tracker_kind.make_empty
			create tracker_provider.make_empty
			create required_labels.make (0)
			create active_states.make (0)
			create terminal_states.make (0)
			create state_concurrency.make (5)
			create codex_command.make_from_string ("codex app-server")
			create workspace_root.make_empty
			apply_defaults
			read_config (a_workflow.config)
			validate
		ensure
			source_path_set: workflow_path.is_equal (a_workflow.path)
		end

feature -- Status

	is_valid: BOOLEAN
		do
			Result := error = Void
		ensure
			valid_tracker_profile: Result implies
				(not tracker_kind.is_empty and then not active_states.is_empty and then not terminal_states.is_empty)
			valid_numeric_settings: Result implies
				(poll_interval_ms > 0 and then hook_timeout_ms > 0 and then max_concurrent_agents > 0 and then
				max_turns > 0 and then max_retry_backoff_ms > 0 and then turn_timeout_ms > 0 and then read_timeout_ms > 0)
			valid_codex_command: Result implies not strings.is_blank (codex_command)
		end

	error: detachable SYM_ERROR

feature -- Source

	workflow_path: PATH

feature -- Tracker

	tracker_kind: STRING_32

	tracker_provider: JSON_OBJECT

	required_labels: ARRAYED_LIST [STRING_32]

	active_states: ARRAYED_LIST [STRING_32]

	terminal_states: ARRAYED_LIST [STRING_32]

feature -- Polling and workspace

	poll_interval_ms: INTEGER_64

	workspace_root: PATH

feature -- Hooks

	after_create_hook: detachable STRING_32

	before_run_hook: detachable STRING_32

	after_run_hook: detachable STRING_32

	before_remove_hook: detachable STRING_32

	hook_timeout_ms: INTEGER_64

feature -- Agent

	max_concurrent_agents: INTEGER

	max_turns: INTEGER

	max_retry_backoff_ms: INTEGER_64

	state_concurrency: HASH_TABLE [INTEGER, STRING_32]

feature -- Codex

	codex_command: STRING_32

	approval_policy: JSON_VALUE

	thread_sandbox: JSON_VALUE

	turn_sandbox_policy: detachable JSON_VALUE

	turn_timeout_ms: INTEGER_64

	read_timeout_ms: INTEGER_64

	stall_timeout_ms: INTEGER_64

feature -- Queries

	is_active_state (a_state: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := normalized_list_has (active_states, a_state)
		ensure
			definition: Result = normalized_list_has (active_states, a_state)
			blank_state_rejected: strings.is_blank (a_state) implies not Result
		end

	is_terminal_state (a_state: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := normalized_list_has (terminal_states, a_state)
		ensure
			definition: Result = normalized_list_has (terminal_states, a_state)
			blank_state_rejected: strings.is_blank (a_state) implies not Result
		end

	state_limit (a_state: READABLE_STRING_GENERAL): INTEGER
		local
			k: STRING_32
		do
			k := strings.normalized (a_state)
			if state_concurrency.has (k) then
				Result := state_concurrency.found_item
			else
				Result := max_concurrent_agents
			end
		ensure
			positive_when_valid: is_valid implies Result > 0
			configured_limit: state_concurrency.has (strings.normalized (a_state)) implies
				Result = state_concurrency.found_item
			default_limit: not state_concurrency.has (strings.normalized (a_state)) implies
				Result = max_concurrent_agents
		end

feature {NONE} -- Defaults

	apply_defaults
		local
			p: JSON_OBJECT
		do
			poll_interval_ms := 30_000
			hook_timeout_ms := 60_000
			max_concurrent_agents := 10
			max_turns := 20
			max_retry_backoff_ms := 300_000
			turn_timeout_ms := 3_600_000
			read_timeout_ms := 5_000
			stall_timeout_ms := 300_000
			create {JSON_STRING} approval_policy.make_from_string ("on-request")
			create {JSON_STRING} thread_sandbox.make_from_string ("workspace-write")
			create p.make_empty
			p.put_string ("workspaceWrite", "type")
			p.put_boolean (False, "networkAccess")
			turn_sandbox_policy := p
			if attached environment.temporary_directory_path as t then
				workspace_root := t.extended ("symphony_workspaces").canonical_path
			else
				workspace_root := workflow_path.parent.extended ("symphony_workspaces").canonical_path
			end
		end

feature {NONE} -- Extraction

	read_config (root: JSON_OBJECT)
		local
			o: detachable JSON_OBJECT
			v: detachable JSON_VALUE
		do
			o := json.object (root, "tracker")
			if root.has_key ("tracker") and then not attached o then
				set_error ("invalid_tracker_config", "tracker must be an object")
			end
			if attached o as tracker then
				if attached json.string (tracker, "kind") as s then
					tracker_kind := strings.trimmed (s)
				elseif tracker.has_key ("kind") then
					set_error ("invalid_tracker_config", "tracker.kind must be a string")
				end
				if attached json.object (tracker, "provider") as p then
					if attached {JSON_OBJECT} json.cloned (p) as cp then tracker_provider := cp end
				elseif tracker.has_key ("provider") then
					set_error ("invalid_tracker_config", "tracker.provider must be an object")
				end
				if tracker.has_key ("required_labels") and then not is_string_array (tracker.item ("required_labels")) then
					set_error ("invalid_tracker_config", "tracker.required_labels must be an array of strings")
				end
				if tracker.has_key ("active_states") and then not is_string_array (tracker.item ("active_states")) then
					set_error ("invalid_tracker_config", "tracker.active_states must be an array of strings")
				end
				if tracker.has_key ("terminal_states") and then not is_string_array (tracker.item ("terminal_states")) then
					set_error ("invalid_tracker_config", "tracker.terminal_states must be an array of strings")
				end
				required_labels := normalized_required_labels (json.string_list (tracker, "required_labels"))
				active_states := normalized_values (json.string_list (tracker, "active_states"), False)
				terminal_states := normalized_values (json.string_list (tracker, "terminal_states"), False)
			end

			o := json.object (root, "polling")
			if root.has_key ("polling") and then not attached o then set_error ("invalid_config", "polling must be an object") end
			if attached o as polling then
				if attached json.integer_64 (polling, "interval_ms") as n then
					poll_interval_ms := n.item
				elseif polling.has_key ("interval_ms") then
					set_error ("invalid_config", "polling.interval_ms must be an integer")
				end
			end

			o := json.object (root, "workspace")
			if root.has_key ("workspace") and then not attached o then set_error ("invalid_config", "workspace must be an object") end
			if attached o as workspace then
				if attached json.string (workspace, "root") as s then
					set_workspace_root (s)
				elseif workspace.has_key ("root") then
					set_error ("invalid_config", "workspace.root must be a string")
				end
			end

			o := json.object (root, "hooks")
			if root.has_key ("hooks") and then not attached o then set_error ("invalid_config", "hooks must be an object") end
			if attached o as hooks then
				after_create_hook := json.string (hooks, "after_create")
				before_run_hook := json.string (hooks, "before_run")
				after_run_hook := json.string (hooks, "after_run")
				before_remove_hook := json.string (hooks, "before_remove")
				if has_non_string (hooks, "after_create") or else has_non_string (hooks, "before_run") or else
					has_non_string (hooks, "after_run") or else has_non_string (hooks, "before_remove")
				then
					set_error ("invalid_config", "workspace hook commands must be strings")
				end
				if attached json.integer_64 (hooks, "timeout_ms") as n then
					hook_timeout_ms := n.item
				elseif hooks.has_key ("timeout_ms") then
					set_error ("invalid_config", "hooks.timeout_ms must be an integer")
				end
			end

			o := json.object (root, "agent")
			if root.has_key ("agent") and then not attached o then set_error ("invalid_config", "agent must be an object") end
			if attached o as agent_config then
				if attached json.integer_64 (agent_config, "max_concurrent_agents") as n and then n.item >= -2147483648 and then n.item <= 2147483647 then
					max_concurrent_agents := n.item.to_integer_32
				elseif agent_config.has_key ("max_concurrent_agents") then
					set_error ("invalid_config", "agent.max_concurrent_agents must be a 32-bit integer")
				end
				if attached json.integer_64 (agent_config, "max_turns") as n and then n.item >= -2147483648 and then n.item <= 2147483647 then
					max_turns := n.item.to_integer_32
				elseif agent_config.has_key ("max_turns") then
					set_error ("invalid_config", "agent.max_turns must be a 32-bit integer")
				end
				if attached json.integer_64 (agent_config, "max_retry_backoff_ms") as n then
					max_retry_backoff_ms := n.item
				elseif agent_config.has_key ("max_retry_backoff_ms") then
					set_error ("invalid_config", "agent.max_retry_backoff_ms must be an integer")
				end
				if attached json.object (agent_config, "max_concurrent_agents_by_state") as limits then
					read_state_limits (limits)
				elseif agent_config.has_key ("max_concurrent_agents_by_state") then
					set_error ("invalid_config", "agent.max_concurrent_agents_by_state must be an object")
				end
			end

			o := json.object (root, "codex")
			if root.has_key ("codex") and then not attached o then set_error ("invalid_config", "codex must be an object") end
			if attached o as codex then
				if attached json.string (codex, "command") as s then codex_command := s elseif codex.has_key ("command") then set_error ("invalid_config", "codex.command must be a string") end
				v := codex.item ("approval_policy")
				if attached v and then not attached {JSON_NULL} v then approval_policy := json.cloned (v) end
				v := codex.item ("thread_sandbox")
				if attached v and then not attached {JSON_NULL} v then thread_sandbox := json.cloned (v) end
				v := codex.item ("turn_sandbox_policy")
				if attached v and then not attached {JSON_NULL} v then turn_sandbox_policy := json.cloned (v) end
				if attached json.integer_64 (codex, "turn_timeout_ms") as n then turn_timeout_ms := n.item elseif codex.has_key ("turn_timeout_ms") then set_error ("invalid_config", "codex.turn_timeout_ms must be an integer") end
				if attached json.integer_64 (codex, "read_timeout_ms") as n then read_timeout_ms := n.item elseif codex.has_key ("read_timeout_ms") then set_error ("invalid_config", "codex.read_timeout_ms must be an integer") end
				if attached json.integer_64 (codex, "stall_timeout_ms") as n then stall_timeout_ms := n.item elseif codex.has_key ("stall_timeout_ms") then set_error ("invalid_config", "codex.stall_timeout_ms must be an integer") end
			end
		end

	read_state_limits (a_object: JSON_OBJECT)
		local
			k: STRING_32
		do
			across a_object as c loop
				if attached {JSON_NUMBER} c.item as n and then n.item.is_integer_64 and then
					n.item.to_integer_64 > 0 and then n.item.to_integer_64 <= 2147483647
				then
					k := strings.normalized (c.key.unescaped_string_32)
					if not k.is_empty then state_concurrency.force (n.item.to_integer_64.to_integer_32, k) end
				end
			end
		end

	set_workspace_root (a_raw: STRING_32)
		local
			expanded_value: detachable STRING_32
			p: PATH
		do
			if strings.is_blank (a_raw) then
				set_error ("invalid_workspace_root", "workspace.root must not be blank")
			else
				expanded_value := expanded_path (a_raw)
			end
			if error = Void and then attached expanded_value as s then
				create p.make_from_string (s)
				if p.is_absolute then
					workspace_root := p.canonical_path
				else
					workspace_root := p.absolute_path_in (workflow_path.parent.canonical_path).canonical_path
				end
			elseif error = Void then
				set_error ("invalid_workspace_root", "workspace.root references a missing environment variable")
			end
		end

	expanded_path (a_raw: STRING_32): detachable STRING_32
		local
			s, name, rest: STRING_32
			i: INTEGER
		do
			s := strings.trimmed (a_raw)
			if s.starts_with ("~") and then (s.count = 1 or else s [2] = '/' or else s [2] = '\') then
				if attached environment.home_directory_path as h then
					if s.count = 1 then Result := h.name else Result := h.name + s.substring (2, s.count) end
				end
			elseif s.starts_with ("$") then
				from i := 2 until i > s.count or else not is_env_character (s [i]) loop i := i + 1 end
				if i > 2 then
					name := s.substring (2, i - 1)
					if i <= s.count then rest := s.substring (i, s.count) else create rest.make_empty end
					if attached environment.item (name) as value and then not value.is_empty then Result := value + rest end
				end
			else
				Result := s
			end
		end

	normalized_values (a_values: ITERABLE [READABLE_STRING_GENERAL]; a_lower: BOOLEAN): ARRAYED_LIST [STRING_32]
		local
			s: STRING_32
		do
			create Result.make (5)
			across a_values as c loop
				if a_lower then s := strings.normalized (c.item) else s := strings.trimmed (c.item) end
				if not s.is_empty and then not Result.has (s) then Result.extend (s) end
			end
		end

	normalized_required_labels (a_values: ITERABLE [READABLE_STRING_GENERAL]): ARRAYED_LIST [STRING_32]
		local
			s: STRING_32
		do
			create Result.make (5)
			across a_values as cursor loop
				s := strings.trimmed (cursor.item)
				if not Result.has (s) then Result.extend (s) end
			end
		end

	is_string_array (a_value: detachable JSON_VALUE): BOOLEAN
		do
			if attached {JSON_ARRAY} a_value as values then
				Result := True
				across values as cursor until not Result loop Result := attached {JSON_STRING} cursor.item end
			end
		end

	has_non_string (a_object: JSON_OBJECT; a_key: READABLE_STRING_8): BOOLEAN
		do
			Result := a_object.has_key (a_key) and then not attached {JSON_STRING} a_object.item (a_key)
		end

feature {NONE} -- Validation

	validate
		do
			if tracker_kind.is_empty then
				set_error ("invalid_tracker_config", "tracker.kind is required")
			elseif active_states.is_empty then
				set_error ("invalid_tracker_config", "tracker.active_states is required for this adapter profile")
			elseif terminal_states.is_empty then
				set_error ("invalid_tracker_config", "tracker.terminal_states is required for this adapter profile")
			elseif poll_interval_ms <= 0 then
				set_error ("invalid_config", "polling.interval_ms must be positive")
			elseif hook_timeout_ms <= 0 then
				set_error ("invalid_config", "hooks.timeout_ms must be positive")
			elseif max_concurrent_agents <= 0 then
				set_error ("invalid_config", "agent.max_concurrent_agents must be positive")
			elseif max_turns <= 0 then
				set_error ("invalid_config", "agent.max_turns must be positive")
			elseif max_retry_backoff_ms <= 0 then
				set_error ("invalid_config", "agent.max_retry_backoff_ms must be positive")
			elseif strings.is_blank (codex_command) then
				set_error ("invalid_config", "codex.command must be non-empty")
			elseif turn_timeout_ms <= 0 then
				set_error ("invalid_config", "codex.turn_timeout_ms must be positive")
			elseif read_timeout_ms <= 0 then
				set_error ("invalid_config", "codex.read_timeout_ms must be positive")
			end
		end

	set_error (a_code, a_message: READABLE_STRING_GENERAL)
		do
			if error = Void then create error.make (a_code, a_message) end
		end

	normalized_list_has (a_list: ITERABLE [READABLE_STRING_GENERAL]; a_value: READABLE_STRING_GENERAL): BOOLEAN
		local
			v: STRING_32
		do
			v := strings.normalized (a_value)
			across a_list as c until Result loop Result := strings.normalized (c.item).same_string (v) end
		end

	is_env_character (c: CHARACTER_32): BOOLEAN
		do
			Result := (c >= 'A' and c <= 'Z') or else (c >= 'a' and c <= 'z') or else
				(c >= '0' and c <= '9') or else c = '_'
		end

feature {NONE} -- Shared helpers

	json: SYM_JSON once create Result end

	strings: SYM_STRINGS once create Result end

	environment: EXECUTION_ENVIRONMENT once create Result end

invariant
	provider_attached: tracker_provider /= Void
	state_limits_attached: state_concurrency /= Void
	positive_state_limits: across state_concurrency as cursor all cursor.item > 0 end

end
