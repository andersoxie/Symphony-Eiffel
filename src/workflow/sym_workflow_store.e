note
	description: "Dynamically reloads WORKFLOW.md while retaining the last known good effective configuration."

class
	SYM_WORKFLOW_STORE

create
	make

feature {NONE} -- Initialization

	make (a_path: PATH)
		do
			path := a_path.canonical_path
			create loader.make
			reload
		end

feature -- Access

	path: PATH

	workflow: detachable SYM_WORKFLOW

	config: detachable SYM_CONFIG

	last_error: detachable SYM_ERROR

	changed: BOOLEAN

	is_ready: BOOLEAN
		do
			Result := workflow /= Void and config /= Void
		end

feature -- Reload

	reload
		local
			candidate: SYM_CONFIG
			old_signature: detachable STRING_32
		do
			changed := False
			last_error := Void
			if attached workflow as previous_workflow then old_signature := previous_workflow.signature end
			loader.load (path)
			if attached loader.workflow as w then
				create candidate.make (w)
				if candidate.is_valid then
					if old_signature = Void or else not old_signature.same_string (w.signature) then changed := True end
					workflow := w
					config := candidate
				else
					last_error := candidate.error
				end
			else
				last_error := loader.error
			end
		end

	reload_if_changed
			-- Content hashes make this a defensive reload even if file-system watch events are lost.
		do
			reload
		end

feature {NONE} -- Implementation

	loader: SYM_WORKFLOW_LOADER

end
