note
	description: "Concrete AutoTest root; avoids the unsupported all-classes/ANY test root."

class
	SYM_TEST_ROOT

create
	make

feature {NONE} -- Initialization

	make
		local
			core: TEST_SYM_CORE
			prompt: TEST_SYM_PROMPT_RENDERER
			yaml: TEST_SYM_YAML_PARSER
		do
			create core
			core.test_sha_256
			core.test_workspace_key_collision_resistance
			core.test_jsonl_complete_line_limit
			core.test_config_defaults
			core.test_blank_workspace_root_is_rejected
			core.test_issue_codec_and_memory_tracker
			core.test_secret_native_ref_normalizes_to_null
			core.test_json_tracker_rejects_duplicate_identity
			core.test_rfc3339_offsets
			core.test_label_routing_uses_value_comparison
			core.test_retry_backoff_and_dispatch_order
			core.test_clock_rfc3339_shape

			create prompt
			prompt.test_fields_nested_values_indices_and_filters
			prompt.test_if_else_and_blocker_loop
			prompt.test_null_attempt_and_empty_loop
			prompt.test_unknown_variable_fails
			prompt.test_unknown_filter_fails
			prompt.test_malformed_in_unselected_branch_fails

			create yaml
			yaml.test_workflow_shaped_document
			yaml.test_scalars_and_flow_collections
			yaml.test_block_scalar_styles_and_chomping
			yaml.test_rejects_malformed_documents

			io.put_string ("22 Eiffel tests passed.%N")
		end

end
