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
			github: TEST_SYM_GITHUB_TRACKER
			process_output: TEST_SYM_PROCESS_OUTPUT
			gateway: TEST_SYM_TRACKER_GATEWAY
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

			create github
			github.test_configuration_invalidates_previous_source
			github.test_configuration_boundaries
			github.test_paginated_snapshot_and_process_arguments
			github.test_refresh_failure_empty_recovery_and_missing_issue
			github.test_transport_and_payload_failures_are_atomic
			github.test_empty_reads_and_secret_environment_names
			github.test_codec_mapping_native_reference_and_pull_request_reset
			github.test_codec_rejects_malformed_required_fields_and_recovers

			create process_output
			process_output.test_default_capture_limit
			process_output.test_capture_boundaries_and_independent_streams
			process_output.test_overflow_is_sticky
			process_output.test_snapshot_independence
			process_output.test_shell_runner_large_output_and_overflow
			process_output.test_shell_runner_timeout_and_reuse

			create gateway
			gateway.test_secret_names_survive_adapter_replacements

			io.put_string ("37 Eiffel tests passed.%N")
		end

end
