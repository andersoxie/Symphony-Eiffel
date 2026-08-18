note
	description: "Pure scheduling, routing, ordering, and retry-backoff policy."

class
	SYM_DISPATCH_POLICY

feature -- Eligibility

	is_routable (a_issue: SYM_ISSUE; a_config: SYM_CONFIG): BOOLEAN
		do
			Result := a_issue.dispatchable and then has_required_labels (a_issue, a_config.required_labels)
		ensure
			definition:
				Result = (a_issue.dispatchable and then
					has_required_labels (a_issue, a_config.required_labels))
		end

	is_candidate (a_issue: SYM_ISSUE; a_config: SYM_CONFIG): BOOLEAN
		do
			Result := a_issue.is_core_valid and then a_config.is_active_state (a_issue.state) and then
				not a_config.is_terminal_state (a_issue.state) and then is_routable (a_issue, a_config)
		ensure
			definition:
				Result = (a_issue.is_core_valid and then a_config.is_active_state (a_issue.state) and then
					not a_config.is_terminal_state (a_issue.state) and then is_routable (a_issue, a_config))
		end

	has_required_labels (a_issue: SYM_ISSUE; a_required: ITERABLE [STRING_32]): BOOLEAN
		local
			found: BOOLEAN
		do
			Result := True
			across a_required as required_cursor until not Result loop
				found := False
				across a_issue.labels as label_cursor until found loop
					found := strings.normalized (label_cursor.item).same_string (
						strings.normalized (required_cursor.item))
				end
				Result := found
			end
		ensure
			empty_finite_requirements:
				attached {FINITE [STRING_32]} a_required as finite_required and then
					finite_required.is_empty implies Result
		end

feature -- Ordering

	sorted_for_dispatch (a_issues: ITERABLE [SYM_ISSUE]): ARRAYED_LIST [SYM_ISSUE]
		local
			position: INTEGER
		do
			create Result.make (10)
			across a_issues as issue_cursor loop
				from position := 1 until position > Result.count or else comes_before (issue_cursor.item, Result [position]) loop
					position := position + 1
				end
				if position > Result.count then
					Result.extend (issue_cursor.item)
				else
					Result.go_i_th (position)
					Result.put_left (issue_cursor.item)
				end
			end
		ensure
			dispatch_ordered: is_dispatch_sorted (Result)
		end

	comes_before (a_left, a_right: SYM_ISSUE): BOOLEAN
		local
			left_bucket, right_bucket: INTEGER_64
		do
			left_bucket := priority_bucket (a_left)
			right_bucket := priority_bucket (a_right)
			if left_bucket /= right_bucket then
				Result := left_bucket < right_bucket
			elseif attached a_left.created_at as left_date and attached a_right.created_at as right_date then
				if not left_date.is_equal (right_date) then
					Result := left_date < right_date
				else
					Result := a_left.identifier < a_right.identifier
				end
			elseif attached a_left.created_at then
				Result := True
			elseif attached a_right.created_at then
				Result := False
			else
				Result := a_left.identifier < a_right.identifier
			end
		ensure
			same_object_not_before: a_left = a_right implies not Result
		end

feature -- Retry

	failure_delay_ms (a_attempt: INTEGER; a_cap_ms: INTEGER_64): INTEGER_64
		require
			attempt_positive: a_attempt >= 1
			cap_positive: a_cap_ms > 0
		local
			index: INTEGER
		do
			if a_cap_ms < 10_000 then Result := a_cap_ms else Result := 10_000 end
			from index := 1 until index >= a_attempt or else Result >= a_cap_ms loop
				if Result > a_cap_ms // 2 then Result := a_cap_ms else Result := (Result * 2).min (a_cap_ms) end
				index := index + 1
			end
		ensure
			positive: Result > 0
			within_cap: Result <= a_cap_ms
		end

	continuation_delay_ms: INTEGER_64 = 1_000

feature {NONE} -- Implementation

	priority_bucket (a_issue: SYM_ISSUE): INTEGER_64
		do
			Result := 5
			if attached a_issue.priority as value and then value.item >= 1 and then value.item <= 4 then
				Result := value.item
			end
		end

	strings: SYM_STRINGS
		once
			create Result
		end

	is_dispatch_sorted (a_values: ARRAYED_LIST [SYM_ISSUE]): BOOLEAN
		local
			i: INTEGER
		do
			Result := True
			from i := 2 until i > a_values.count or else not Result loop
				Result := not comes_before (a_values [i], a_values [i - 1])
				i := i + 1
			end
		end

end
