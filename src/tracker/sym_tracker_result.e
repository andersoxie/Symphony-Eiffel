note
	description: "Immutable result of one serialized tracker read."

class
	SYM_TRACKER_RESULT

create
	make

feature {NONE} -- Initialization

	make (a_issues: ITERABLE [SYM_ISSUE]; a_error: detachable SYM_ERROR)
		do
			create issues.make (5)
			across a_issues as cursor loop
				issues.extend (cursor.item)
			end
			error := a_error
		ensure
			error_set: error = a_error
			fresh_issue_container: issues /= a_issues
		end

feature -- Access

	issues: ARRAYED_LIST [SYM_ISSUE]

	error: detachable SYM_ERROR

	is_success: BOOLEAN
		do
			Result := error = Void
		ensure
			definition: Result = (error = Void)
		end

end
