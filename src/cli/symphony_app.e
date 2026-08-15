note
	description: "Symphony Eiffel command-line service entry point."

class
	SYMPHONY_APP

inherit
	ARGUMENTS_32

create
	make

feature {NONE} -- Initialization

	make
		local
			workflow_path: PATH
			store: SYM_WORKFLOW_STORE
			logger: SYM_LOGGER
			orchestrator: SYM_ORCHESTRATOR
		do
			parse_arguments
			if show_help then
				print_usage (io.output)
			elseif attached argument_error as parse_error then
				io.error.put_string ("error: " + parse_error + "%N%N")
				print_usage (io.error)
				exceptions.die (2)
			else
				workflow_path := selected_workflow_path
				create logger.make_stdout
				create store.make (workflow_path)
				create orchestrator.make (store, logger)
				if not orchestrator.is_ready then
					if attached orchestrator.last_error as startup_error then
						io.error.put_string (startup_error.out + "%N")
					else
						io.error.put_string ("invalid_workflow: startup validation failed%N")
					end
					exceptions.die (2)
				elseif validate_only then
					io.put_string (strings.utf_8 ("Workflow and tracker configuration are valid: " + workflow_path.name + "%N"))
				elseif once_only then
					orchestrator.run_once
					exit_on_runtime_error (orchestrator)
				else
					orchestrator.run
					exit_on_runtime_error (orchestrator)
				end
			end
		end

feature {NONE} -- Arguments

	parse_arguments
		local
			i: INTEGER
			value: STRING_32
		do
			from i := 1 until i > argument_count or else argument_error /= Void loop
				value := argument (i).to_string_32
				if value.same_string ("--help") or else value.same_string ("-h") then
					show_help := True
				elseif value.same_string ("--validate") then
					if once_only then argument_error := "--validate and --once are mutually exclusive" else validate_only := True end
				elseif value.same_string ("--once") then
					if validate_only then argument_error := "--validate and --once are mutually exclusive" else once_only := True end
				elseif value.starts_with ("-") then
					argument_error := "unknown option: " + value
				elseif workflow_argument = Void then
					workflow_argument := value
				else
					argument_error := "only one WORKFLOW.md path may be supplied"
				end
				i := i + 1
			end
		end

	selected_workflow_path: PATH
		local
			candidate: PATH
		do
			if attached workflow_argument as value then
				create candidate.make_from_string (value)
			else
				candidate := environment.current_working_path.extended ("WORKFLOW.md")
			end
			if candidate.is_absolute then
				Result := candidate.canonical_path
			else
				Result := candidate.absolute_path_in (environment.current_working_path).canonical_path
			end
		end

	print_usage (a_output: FILE)
		do
			a_output.put_string ("Usage: symphony [--validate | --once] [path-to-WORKFLOW.md]%N")
			a_output.put_string ("%N")
			a_output.put_string ("  --validate  Validate workflow, configuration, and tracker profile; do no work.%N")
			a_output.put_string ("  --once      Run one scheduling cycle and wait for dispatched work to finish.%N")
			a_output.put_string ("  --help      Show this help.%N")
		end

	workflow_argument: detachable STRING_32

	argument_error: detachable STRING_32

	validate_only, once_only, show_help: BOOLEAN

feature {NONE} -- Runtime

	exit_on_runtime_error (a_orchestrator: SYM_ORCHESTRATOR)
		do
			if attached a_orchestrator.last_error as runtime_error then
				io.error.put_string (runtime_error.out + "%N")
				exceptions.die (1)
			end
		end

	environment: EXECUTION_ENVIRONMENT
		once
			create Result
		end

	exceptions: EXCEPTIONS
		once
			create Result
		end

	strings: SYM_STRINGS
		once
			create Result
		end

end
