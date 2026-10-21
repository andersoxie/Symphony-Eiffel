note
	testing: "execution/serial/symphony"

class
	TEST_SYM_TRACKER_GATEWAY

inherit
	EQA_TEST_SET

feature -- Reload lifecycle

	test_secret_names_survive_adapter_replacements
		local
			github, next_github: SYM_GITHUB_TRACKER
			memory: SYM_MEMORY_TRACKER
			file_tracker: SYM_JSON_FILE_TRACKER
			gateway, late_worker_gateway: SYM_TRACKER_GATEWAY
			names: ARRAYED_LIST [STRING_32]
		do
			create github.make
			create gateway.make (github)
			late_worker_gateway := gateway
			names := gateway.secret_environment_names
			assert ("initial GitHub credentials excluded", has_github_names (names))
			-- Callers own both the returned list and its strings.
			names.first.wipe_out
			names.wipe_out
			assert ("snapshot mutation cannot reduce filter", has_github_names (gateway.secret_environment_names))
			create memory.make
			gateway.replace_adapter (memory)
			assert ("adapter replaced", gateway.kind.same_string ("memory"))
			assert ("old worker retains GitHub exclusions after memory replacement", has_github_names (late_worker_gateway.secret_environment_names))
			create next_github.make
			gateway.replace_adapter (next_github)
			assert ("repeated declarations deduplicate", has_github_names (gateway.secret_environment_names))
			create file_tracker.make
			gateway.replace_adapter (file_tracker)
			assert ("file adapter selected", gateway.kind.same_string ("json_file"))
			assert ("old worker retains exclusions across alternating replacements", has_github_names (late_worker_gateway.secret_environment_names))
		end

feature {NONE} -- Assertions

	has_github_names (a_names: ARRAYED_LIST [STRING_32]): BOOLEAN
		do
			a_names.compare_objects
			Result := a_names.count = 4 and then a_names.has ("GH_TOKEN") and then
				a_names.has ("GITHUB_TOKEN") and then a_names.has ("GH_ENTERPRISE_TOKEN") and then
				a_names.has ("GITHUB_ENTERPRISE_TOKEN")
		end

end
