note
	description: "Focused tests for the native Symphony YAML subset parser."
	license: "Apache-2.0"
	testing: "execution/serial/symphony"

class
	TEST_SYM_YAML_PARSER

inherit
	EQA_TEST_SET

feature -- Tests

	test_workflow_shaped_document
		local
			p: SYM_YAML_PARSER
		do
			create p.make
			p.parse ("---%Ntracker:%N  kind: linear%N  active_states:%N    - Todo%N    - In Progress%N  provider: {token: $TOKEN, enabled: true}%Nagent:%N  max_concurrent_agents: 4%Nhooks:%N  after_create: |-%N    git init%N    echo ready%N...")
			assert ("document is valid", p.is_valid)
			if attached p.root as r then
				if attached r.object_item ("tracker") as tracker then
					assert ("tracker kind", attached tracker.string_item ("kind") as kind and then kind.same_string ("linear"))
					assert ("states", attached tracker.array_item ("active_states") as states and then states.count = 2)
					if attached tracker.object_item ("provider") as provider then
						assert ("provider token", attached provider.string_item ("token") as token and then token.same_string ("$TOKEN"))
						assert ("provider boolean", attached provider.boolean_item ("enabled") as enabled and then enabled.item)
					else
						assert ("provider object", False)
					end
				else
					assert ("tracker object", False)
				end
				assert ("integer", attached r.object_item ("agent") as agent_config and then attached agent_config.number_item ("max_concurrent_agents") as maximum and then maximum.integer_64_item = 4)
				assert ("hook", attached r.object_item ("hooks") as hooks and then attached hooks.string_item ("after_create") as script and then script.same_string ("git init%Necho ready"))
			else
				assert ("root object", False)
			end
			p.parse ("clip_without_final_break: |%N  text")
			assert ("clip respects end of input", attached p.root as clipped_root and then attached clipped_root.string_item ("clip_without_final_break") as clipped and then clipped.same_string ("text"))
			p.parse ("empty_clip: >%N%Nnext: value")
			assert ("empty clip", attached p.root as empty_root and then attached empty_root.string_item ("empty_clip") as empty_value and then empty_value.same_string (""))
			p.parse ("folded_keep: >+%N  one%N%N%Nnext: value")
			assert ("fold keep", attached p.root as keep_root and then attached keep_root.string_item ("folded_keep") as folded_keep and then folded_keep.same_string ("one%N%N%N"))
		end

	test_scalars_and_flow_collections
		local
			p: SYM_YAML_PARSER
		do
			create p.make
			p.parse ("plain: hello # ignored%Nhash: value#part%Npunctuation: hello, [world] and {friends}%Nsingle: 'it''s fine'%Ndouble: %"line\nnext%"%Npositive: +42%Nnegative: -7%Ntruth: TRUE%Nfalsehood: false%Nnone: null%Ntilde: ~%Nempty_list: []%Nempty_map: {}%Nempty_flow_value: {value:}%Nflow: [one, {two: 2}, three,]")
			assert ("document is valid", p.is_valid)
			if attached p.root as r then
				assert ("plain comment", attached r.string_item ("plain") as plain and then plain.same_string ("hello"))
				assert ("embedded hash", attached r.string_item ("hash") as hash and then hash.same_string ("value#part"))
				assert ("block punctuation", attached r.string_item ("punctuation") as punctuation and then punctuation.same_string ("hello, [world] and {friends}"))
				assert ("single quote", attached r.string_item ("single") as single and then single.same_string ("it's fine"))
				assert ("double quote escape", attached r.string_item ("double") as double and then double.same_string ("line%Nnext"))
				assert ("positive integer", attached r.number_item ("positive") as positive and then positive.integer_64_item = 42)
				assert ("negative integer", attached r.number_item ("negative") as negative and then negative.integer_64_item = -7)
				assert ("true", attached r.boolean_item ("truth") as truth and then truth.item)
				assert ("false", attached r.boolean_item ("falsehood") as falsehood and then not falsehood.item)
				assert ("null", attached r.item ("none") as none and then none.is_null)
				assert ("tilde null", attached r.item ("tilde") as tilde and then tilde.is_null)
				assert ("empty list", attached r.array_item ("empty_list") as empty_list and then empty_list.is_empty)
				assert ("empty map", attached r.object_item ("empty_map") as empty_map and then empty_map.is_empty)
				assert ("empty flow value", attached r.object_item ("empty_flow_value") as empty_flow_value and then attached empty_flow_value.item ("value") as null_value and then null_value.is_null)
				assert ("nested flow", attached r.array_item ("flow") as flow and then flow.count = 3 and then attached {JSON_OBJECT} flow.i_th (2) as inner and then attached inner.number_item ("two") as two and then two.integer_64_item = 2)
			else
				assert ("root object", False)
			end
		end

	test_block_scalar_styles_and_chomping
		local
			p: SYM_YAML_PARSER
		do
			create p.make
			p.parse ("literal: |%N  one%N  two%Nstripped: |-%N  one%Nkept: |+%N  one%N%N%Nfolded: >%N  one%N  two%N%N  three%Nscripts:%N  - |-%N    echo first%N    echo second")
			assert ("document is valid", p.is_valid)
			if attached p.root as r then
				assert ("literal", attached r.string_item ("literal") as literal and then literal.same_string ("one%Ntwo%N"))
				assert ("strip", attached r.string_item ("stripped") as stripped and then stripped.same_string ("one"))
				assert ("keep", attached r.string_item ("kept") as kept and then kept.same_string ("one%N%N%N"))
				assert ("fold", attached r.string_item ("folded") as folded and then folded.same_string ("one two%Nthree%N"))
				assert ("sequence block", attached r.array_item ("scripts") as scripts and then scripts.count = 1 and then attached {JSON_STRING} scripts.i_th (1) as script and then script.same_string ("echo first%Necho second"))
			else
				assert ("root object", False)
			end
		end

	test_rejects_malformed_documents
		local
			p: SYM_YAML_PARSER
		do
			create p.make
			p.parse ("a: 1%Na: 2")
			assert_invalid_with (p, "duplicate")
			p.parse ("flow: {a: 1, a: 2}")
			assert_invalid_with (p, "duplicate")
			p.parse ("- not%N- a%N- map")
			assert_invalid_with (p, "root")
			p.parse ("a:%N  b: one%N   c: two")
			assert_invalid_with (p, "indentation")
			p.parse ("a:%N%Tbad: 1")
			assert_invalid_with (p, "tabs")
			p.parse ("a: [one, two")
			assert_invalid_with (p, "unterminated")
			p.parse ("a: %"unterminated")
			assert_invalid_with (p, "unterminated")
			p.parse ("a: |x%N  value")
			assert_invalid_with (p, "indicator")
			p.parse ("a: |%N    first%N  less")
			assert_invalid_with (p, "indentation")
		end

feature {NONE} -- Assertions

	assert_invalid_with (a_parser: SYM_YAML_PARSER; a_fragment: READABLE_STRING_GENERAL)
		do
			assert ("invalid document", not a_parser.is_valid)
			assert ("root cleared", a_parser.root = Void)
			assert ("useful error", a_parser.error_message.has_substring (a_fragment.as_string_32))
		end

end
