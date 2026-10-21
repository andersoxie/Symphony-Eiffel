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
			create retained_secret_names.make (4)
			retain_secret_names (a_adapter.secret_environment_names)
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
			-- Snapshot of names declared during this gateway's lifetime. Workers
			-- dispatched before a replacement may still be preparing to launch.
		local
			locked: BOOLEAN
		do
			mutex.lock
			locked := True
			create Result.make (retained_secret_names.count)
			across retained_secret_names as cursor loop Result.extend (cursor.item.twin) end
			mutex.unlock
			locked := False
		ensure
			all_names_present: across Result as name_cursor all
				not name_cursor.item.is_empty
			end
		rescue
			-- Fail the launch if a snapshot cannot be obtained; never return a
			-- reduced secret set after a lock or allocation failure.
			if locked then mutex.unlock end
		end

feature -- Adapter lifecycle

	replace_adapter (a_adapter: SYM_TRACKER_ADAPTER)
			-- Atomically use `a_adapter' for subsequent reads.
		local
			locked: BOOLEAN
		do
			mutex.lock
			locked := True
			-- Extend the filter before publishing the replacement. Retaining old
			-- names protects late launches through this same shared gateway.
			retain_secret_names (a_adapter.secret_environment_names)
			adapter := a_adapter
			adapter_generation := adapter_generation + 1
			mutex.unlock
			locked := False
		ensure
			replacement_recorded: adapter_generation > old adapter_generation
		rescue
			if locked then mutex.unlock end
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

	retain_secret_names (a_names: ITERABLE [STRING_32])
			-- Called during initialization or while the gateway mutex is held.
		local
			already_retained: BOOLEAN
		do
			across a_names as name_cursor loop
				already_retained := False
				across retained_secret_names as existing_cursor until already_retained loop
					already_retained := existing_cursor.item.is_case_insensitive_equal (name_cursor.item)
				end
				if not already_retained then retained_secret_names.extend (name_cursor.item.twin) end
			end
		end

	retained_secret_names: ARRAYED_LIST [STRING_32]
			-- Names only, never environment-variable values.

	adapter: SYM_TRACKER_ADAPTER

	adapter_generation: NATURAL_64

	mutex: MUTEX

end
