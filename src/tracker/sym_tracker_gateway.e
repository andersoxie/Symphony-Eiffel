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
		end

feature -- Access

	kind: STRING_32
		do
			Result := adapter.kind
		end

	secret_environment_names: ARRAYED_LIST [STRING_32]
		do
			mutex.lock
			Result := adapter.secret_environment_names
			mutex.unlock
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
			mutex.unlock
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
		rescue
			if locked then mutex.unlock end
			create Result.make (create {ARRAYED_LIST [SYM_ISSUE]}.make (0),
				create {SYM_ERROR}.make ("tracker_request", "Unexpected tracker adapter failure"))
		end

feature {NONE} -- Implementation

	adapter: SYM_TRACKER_ADAPTER

	mutex: MUTEX

end
