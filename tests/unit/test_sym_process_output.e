note
	testing: "execution/serial/symphony"

class
	TEST_SYM_PROCESS_OUTPUT

inherit
	EQA_TEST_SET

feature -- Capture tests

	test_default_capture_limit
		local
			capture: SYM_PROCESS_OUTPUT
		do
			create capture.make
			assert ("default limit preserved", capture.max_capture_bytes = 65_536)
			assert ("initially empty", capture.output_snapshot.is_empty and capture.error_snapshot.is_empty)
			assert ("initially complete", not capture.has_overflowed)
		end

	test_capture_boundaries_and_independent_streams
		local
			capture: SYM_PROCESS_OUTPUT
		do
			create capture.make_with_limit (4)
			capture.append_output ("ab")
			capture.append_output ("cd")
			capture.append_error ("wxyz")
			capture.append_output ("")
			assert ("stdout exact boundary", capture.output_snapshot.same_string ("abcd"))
			assert ("stderr independent boundary", capture.error_snapshot.same_string ("wxyz"))
			assert ("exact limits complete", not capture.has_overflowed)
			capture.append_error ("q")
			assert ("stderr overflow recorded", capture.has_overflowed)
			assert ("stderr remains bounded", capture.error_snapshot.same_string ("wxyz"))
		end

	test_overflow_is_sticky
		local
			capture: SYM_PROCESS_OUTPUT
		do
			create capture.make_with_limit (4)
			capture.append_output ("abcdef")
			assert ("partial chunk retained", capture.output_snapshot.same_string ("abcd"))
			assert ("partial chunk overflow recorded", capture.has_overflowed)
			capture.append_error ("x")
			capture.append_output ("")
			assert ("later appends preserve overflow", capture.has_overflowed)
			assert ("stderr retained after stdout overflow", capture.error_snapshot.same_string ("x"))
		end

	test_snapshot_independence
		local
			capture: SYM_PROCESS_OUTPUT
			output, errors: STRING_8
		do
			create capture.make_with_limit (4)
			capture.append_output ("ab")
			capture.append_error ("xy")
			output := capture.output_snapshot
			errors := capture.error_snapshot
			output.wipe_out
			errors.append ("z")
			capture.append_output ("c")
			assert ("stdout snapshot cannot mutate storage", capture.output_snapshot.same_string ("abc"))
			assert ("stderr snapshot cannot mutate storage", capture.error_snapshot.same_string ("xy"))
			assert ("snapshot changes do not overflow", not capture.has_overflowed)
		end

feature -- Real process tests

	test_shell_runner_large_output_and_overflow
		local
			large_runner, small_runner: SYM_SHELL_RUNNER
			cwd: PATH
			script: STRING_32
		do
			create cwd.make_current
			if {PLATFORM}.is_windows then
				script := "[Console]::Out.Write(('x' * 70000))"
			else
				script := "printf '%%070000d' 0"
			end
			create large_runner.make_with_output_limit (70_010)
			large_runner.run_hook (script, cwd.absolute_path, 10_000)
			assert ("large process succeeded", large_runner.last_result.is_success)
			assert ("more than legacy limit preserved", large_runner.last_result.output.count = 70_000)
			assert ("large process complete", not large_runner.last_output_truncated)
			create small_runner.make
			small_runner.run_hook (script, cwd.absolute_path, 10_000)
			assert ("hook success retained on truncated output", small_runner.last_result.is_success)
			assert ("default process output bounded", small_runner.last_result.output.count = 65_536)
			assert ("process overflow reported", small_runner.last_output_truncated)
			small_runner.run_hook ("exit 7", cwd.absolute_path, 10_000)
			assert ("next exit status retained", small_runner.last_result.launched and then small_runner.last_result.exit_code = 7)
			assert ("next failure has fresh output", small_runner.last_result.output.is_empty)
			assert ("next run resets truncation", not small_runner.last_output_truncated)
		end

	test_shell_runner_timeout_and_reuse
		local
			runner: SYM_SHELL_RUNNER
			cwd: PATH
			sleep_script, success_script: STRING_32
			child_pid: STRING_8
		do
			create cwd.make_current
			if {PLATFORM}.is_windows then
				sleep_script := "[Console]::Out.Write($PID); Start-Sleep -Seconds 10"
			else
				sleep_script := "printf '%%s' $$; sleep 10"
			end
			create runner.make
			runner.run_hook (sleep_script, cwd.absolute_path, 2_000)
			assert ("sleep launched", runner.last_result.launched)
			assert ("sleep timed out", runner.last_result.timed_out)
			child_pid := runner.last_result.output.twin
			child_pid.left_adjust
			child_pid.right_adjust
			assert ("timed out child recorded PID", child_pid.is_integer_64 and then child_pid.to_integer_64 > 0)
			if {PLATFORM}.is_windows then
				success_script := "if ($null -ne (Get-Process -Id " + child_pid +
					" -ErrorAction SilentlyContinue)) { exit 1 }; [Console]::Out.Write('ok')"
			else
				success_script := "if kill -0 " + child_pid + " 2>/dev/null; then exit 1; fi; printf ok"
			end
			runner.run_hook (success_script, cwd.absolute_path, 10_000)
			assert ("timed out child exited and runner reusable", runner.last_result.is_success)
			assert ("fresh capture after timeout", runner.last_result.output.same_string ("ok"))
			assert ("fresh complete output", not runner.last_output_truncated)
		end

end
