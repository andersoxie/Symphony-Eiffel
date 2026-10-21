note
	description: "Decodes GitHub REST issues into provider-neutral Symphony issues."

class
	SYM_GITHUB_ISSUE_CODEC

create
	make

feature {NONE} -- Initialization

	make
		do
		ensure
			idle: issue = Void and error = Void and not is_pull_request
		end

feature -- Result

	issue: detachable SYM_ISSUE

	error: detachable SYM_ERROR

	is_pull_request: BOOLEAN

feature -- Decoding

	decode (a_object: JSON_OBJECT; a_repository, a_hostname: READABLE_STRING_GENERAL)
			-- Read one REST issue. The repository issues API also returns pull requests.
		local
			i: SYM_ISSUE
			labels: ARRAYED_LIST [STRING_32]
			native: JSON_OBJECT
			host, repository, state, stable_id, identifier: STRING_32
		do
			issue := Void
			error := Void
			is_pull_request := a_object.has_key ("pull_request")
			if not is_pull_request then
				host := strings.normalized (a_hostname)
				repository := strings.normalized (a_repository)
				if host.is_empty or else repository.is_empty then
					create error.make ("tracker_response", "GitHub issue requires a hostname and repository")
				elseif attached json.integer_64 (a_object, "id") as id and then id.item > 0 and then
					attached json.integer_64 (a_object, "number") as number and then number.item > 0 and then
					attached json.string (a_object, "title") as title and then not strings.is_blank (title) and then
					attached json.string (a_object, "state") as raw_state
				then
					state := strings.normalized (raw_state)
					if state.same_string ("open") or else state.same_string ("closed") then
						stable_id := "github:" + host + ":" + id.item.out
						identifier := host + "/" + repository + "#" + number.item.out
						create i.make (stable_id, identifier, title, state)
						i.set_description (json.string (a_object, "body"))
						i.set_url (json.string (a_object, "html_url"))
						if attached json.object (a_object, "assignee") as assignee and then
							attached json.integer_64 (assignee, "id") as assignee_id and then assignee_id.item > 0
						then
							i.set_assignee_id (assignee_id.item.out)
						end
						create labels.make (5)
						if attached json.array (a_object, "labels") as source_labels then
							across source_labels as cursor loop
								if attached {JSON_STRING} cursor.item as label then
									labels.extend (label.unescaped_string_32)
								elseif attached {JSON_OBJECT} cursor.item as label_object and then
									attached json.string (label_object, "name") as name
								then
									labels.extend (name)
								end
							end
						end
						i.set_labels (labels)
						if attached json.string (a_object, "created_at") as created then
							i.set_created_at (dates.parsed (created))
						end
						if attached json.string (a_object, "updated_at") as updated then
							i.set_updated_at (dates.parsed (updated))
						end
						-- Keep provider payloads and credentials outside prompts and logs.
						create native.make_empty
						native.put_string (host, "hostname")
						native.put_string (repository, "repository")
						native.put_integer (number.item, "number")
						i.set_native_ref (native)
						issue := i
					else
						create error.make ("tracker_response", "GitHub issue state must be open or closed")
					end
				else
					create error.make ("tracker_response", "GitHub issue is missing a positive integer id or number, title, or state")
				end
			end
		ensure
			pull_request_ignored: is_pull_request implies issue = Void and error = Void
			complete_issue_result: not is_pull_request implies (issue /= Void) /= (error /= Void)
			decoded_issue_valid: attached issue as decoded_issue implies decoded_issue.is_core_valid
		end

feature {NONE} -- Helpers

	json: SYM_JSON once create Result end

	strings: SYM_STRINGS once create Result end

	dates: SYM_RFC3339 once create Result end

end
