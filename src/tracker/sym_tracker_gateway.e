note
	description: "Single serialized gateway around a possibly stateful tracker adapter."

class
	SYM_TRACKER_GATEWAY

create
	make

feature {NONE} -- Initialization

	make (a_adapter: SYM_TRACKER_ADAPTER)
		do
			adapter := a_adapter
			create mutex.make
		ensure
			adapter_selected: kind.same_string (a_adapter.kind)
			no_replacements: adapter_generation = 0
		end

feature -- Access

	kind: STRING_32
		do
			Result := adapter.kind
		ensure
			present: not Result.is_empty
		end

	secret_environment_names: ARRAYED_LIST [STRING_32]
		do
			mutex.lock
			Result := adapter.secret_environment_names
			mutex.unlock
		ensure
			all_names_present: across Result as name_cursor all
				not name_cursor.item.is_empty
			end
		rescue
			mutex.unlock
			create Result.make (0)
		end

feature -- Adapter lifecycle

	replace_adapter (a_adapter: SYM_TRACKER_ADAPTER)
			-- Atomically use `a_adapter' for subsequent reads.
		do
			mutex.lock
			adapter := a_adapter
			adapter_generation := adapter_generation + 1
			mutex.unlock
		ensure
			replacement_recorded: adapter_generation > old adapter_generation
		rescue
			mutex.unlock
		end

feature -- Reads

	fetch_issues_by_states (a_states: LIST [STRING_32]): SYM_TRACKER_RESULT
		local
			locked: BOOLEAN
		do
			mutex.lock
			locked := True
			adapter.fetch_issues_by_states (a_states)
			create Result.make (adapter.last_issues, adapter.last_error)
			mutex.unlock
			locked := False
		ensure
			empty_short_circuit: a_states.is_empty implies Result.issues.is_empty
			failure_has_no_issues: not Result.is_success implies Result.issues.is_empty
		rescue
			if locked then mutex.unlock end
			create Result.make (create {ARRAYED_LIST [SYM_ISSUE]}.make (0),
				create {SYM_ERROR}.make ("tracker_request", "Unexpected tracker adapter failure"))
		end

	fetch_issues_by_ids (a_ids: LIST [STRING_32]): SYM_TRACKER_RESULT
		local
			locked: BOOLEAN
		do
			mutex.lock
			locked := True
			adapter.fetch_issues_by_ids (a_ids)
			create Result.make (adapter.last_issues, adapter.last_error)
			mutex.unlock
			locked := False
		ensure
			empty_short_circuit: a_ids.is_empty implies Result.issues.is_empty
			failure_has_no_issues: not Result.is_success implies Result.issues.is_empty
		rescue
			if locked then mutex.unlock end
			create Result.make (create {ARRAYED_LIST [SYM_ISSUE]}.make (0),
				create {SYM_ERROR}.make ("tracker_request", "Unexpected tracker adapter failure"))
		end

feature {NONE} -- Implementation

	adapter: SYM_TRACKER_ADAPTER

	adapter_generation: NATURAL_64

	mutex: MUTEX

end
