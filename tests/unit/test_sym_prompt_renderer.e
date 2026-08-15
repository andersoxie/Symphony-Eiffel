note
	testing: "execution/serial/symphony"

class
	TEST_SYM_PROMPT_RENDERER

inherit
	EQA_TEST_SET

feature -- Rendering

	test_fields_nested_values_indices_and_filters
		local
			issue: SYM_ISSUE
			renderer: SYM_PROMPT_RENDERER
			native_ref, owner: JSON_OBJECT
			labels: ARRAYED_LIST [STRING_32]
			attempt: INTEGER_64_REF
		do
			create issue.make ("opaque-42", "EIFFEL-42", "Strict prompts", "Todo")
			issue.set_description ("  Mixed Case  ")
			create labels.make (2)
			labels.extend ("Backend")
			labels.extend ("Urgent")
			issue.set_labels (labels)
			create owner.make_empty
			owner.put_string ("Ada", "name")
			create native_ref.make_empty
			native_ref.put (owner, "owner")
			issue.set_native_ref (native_ref)
			create attempt
			attempt.set_item (3)
			create renderer.make

			renderer.render (
				"{{ issue.identifier | downcase }}|{{ issue.description | strip | upcase }}|{{ issue.native_ref.owner.name }}|{{ issue.labels[1] }}|{{ attempt }}|{{ issue.labels | json }}",
				issue,
				attempt
			)

			assert ("render succeeded", renderer.is_success)
			assert (
				"rendered values",
				renderer.rendered_prompt.same_string ("eiffel-42|MIXED CASE|Ada|urgent|3|[%"backend%",%"urgent%"]")
			)
		end

	test_if_else_and_blocker_loop
		local
			issue: SYM_ISSUE
			renderer: SYM_PROMPT_RENDERER
			first, second: SYM_BLOCKER
		do
			create issue.make ("opaque-9", "EIFFEL-9", "Blocked issue", "Todo")
			create first.make ("dep-1", "DEP-1", "In Progress")
			create second.make ("dep-2", Void, "Todo")
			issue.blocked_by.extend (first)
			issue.blocked_by.extend (second)
			create renderer.make

			renderer.render (
				"{%% if issue.description %%}has body{%% else %%}no body{%% endif %%}{%% for blocker in issue.blocked_by %%}[{{ blocker.identifier | default: 'unknown' }}]{%% endfor %%}",
				issue,
				Void
			)

			assert ("render succeeded", renderer.is_success)
			assert ("selected branch and loop", renderer.rendered_prompt.same_string ("no body[DEP-1][unknown]"))
		end

	test_null_attempt_and_empty_loop
		local
			issue: SYM_ISSUE
			renderer: SYM_PROMPT_RENDERER
		do
			create issue.make ("opaque-1", "EIF-1", "First attempt", "Todo")
			create renderer.make
			renderer.render (
				"A={{ attempt | default: 0 }}{%% for label in issue.labels %%} {{ label }}{%% endfor %%}",
				issue,
				Void
			)
			assert ("render succeeded", renderer.is_success)
			assert ("null defaults and empty array iterates zero times", renderer.rendered_prompt.same_string ("A=0"))
		end

feature -- Strict failures

	test_unknown_variable_fails
		local
			issue: SYM_ISSUE
			renderer: SYM_PROMPT_RENDERER
		do
			create issue.make ("opaque-1", "EIF-1", "Strict", "Todo")
			create renderer.make
			renderer.render ("{{ missing.ticket_id }}", issue, Void)
			assert ("failed", not renderer.is_success)
			assert (
				"render error",
				attached renderer.error as e and then e.code.same_string ("template_render_error")
			)
			assert ("no partial result", renderer.rendered_prompt.is_empty)
		end

	test_unknown_filter_fails
		local
			issue: SYM_ISSUE
			renderer: SYM_PROMPT_RENDERER
		do
			create issue.make ("opaque-1", "EIF-1", "Strict", "Todo")
			create renderer.make
			renderer.render ("{{ issue.title | mystery }}", issue, Void)
			assert ("failed", not renderer.is_success)
			assert (
				"render error",
				attached renderer.error as e and then e.code.same_string ("template_render_error")
			)
		end

	test_malformed_in_unselected_branch_fails
		local
			issue: SYM_ISSUE
			renderer: SYM_PROMPT_RENDERER
		do
			create issue.make ("opaque-1", "EIF-1", "Strict", "Todo")
			create renderer.make
			renderer.render (
				"{%% if true %%}selected{%% else %%}{{ issue.title {%% endif %%}",
				issue,
				Void
			)
			assert ("failed", not renderer.is_success)
			assert (
				"parse error",
				attached renderer.error as e and then e.code.same_string ("template_parse_error")
			)
		end

end
