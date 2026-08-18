note
	description: "OS ownership guard for one app-server process group or Windows Job Object."

class
	SYM_PROCESS_GROUP_GUARD

create
	make

feature {NONE} -- Initialization

	make (a_process_id: INTEGER)
		require
			positive_process_id: a_process_id > 0
		do
			process_id := a_process_id
			native_handle := c_create (a_process_id)
			is_attached := native_handle /= default_pointer
		ensure
			process_id_set: process_id = a_process_id
			attachment_matches_handle: is_attached = (native_handle /= default_pointer)
			termination_not_attempted: not last_termination_successful
		end

feature -- Status

	is_attached: BOOLEAN
			-- Is the launched process owned by this guard?

	has_live_members: BOOLEAN
			-- Does the owned group still contain a live process?
		do
			Result := not is_attached or else c_has_members (native_handle, process_id) /= 0
		ensure
			unattached_is_conservative: not is_attached implies Result
		end

	last_termination_successful: BOOLEAN

feature -- Control

	terminate
			-- Request hard termination of every process in the owned group.
		do
			if is_attached then
				last_termination_successful := c_terminate (native_handle, process_id) /= 0
			else
				last_termination_successful := False
			end
		ensure
			unattached_cannot_terminate: not is_attached implies not last_termination_successful
		end

	close_when_empty
			-- Release the ownership handle only after the group is confirmed empty.
		do
			if is_attached and then not has_live_members then
				c_close (native_handle)
				native_handle := default_pointer
				is_attached := False
			end
		ensure
			unattached_remains_unattached: not (old is_attached) implies not is_attached
			attachment_matches_handle: is_attached = (native_handle /= default_pointer)
		end

feature {NONE} -- Native bridge

	process_id: INTEGER

	native_handle: POINTER

	c_create (a_process_id: INTEGER): POINTER
		external
			"C inline use <sym_process_group_guard.h>"
		alias
			"return (EIF_POINTER) sym_process_group_create((long)$a_process_id);"
		end

	c_terminate (a_handle: POINTER; a_process_id: INTEGER): INTEGER
		external
			"C inline use <sym_process_group_guard.h>"
		alias
			"return (EIF_INTEGER) sym_process_group_terminate((void *)$a_handle, (long)$a_process_id);"
		end

	c_has_members (a_handle: POINTER; a_process_id: INTEGER): INTEGER
		external
			"C inline use <sym_process_group_guard.h>"
		alias
			"return (EIF_INTEGER) sym_process_group_has_members((void *)$a_handle, (long)$a_process_id);"
		end

	c_close (a_handle: POINTER)
		external
			"C inline use <sym_process_group_guard.h>"
		alias
			"sym_process_group_close((void *)$a_handle);"
		end

end
