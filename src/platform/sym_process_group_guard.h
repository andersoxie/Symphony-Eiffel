#ifndef SYM_PROCESS_GROUP_GUARD_H
#define SYM_PROCESS_GROUP_GUARD_H

#if defined(_WIN32)
#  include <windows.h>

static void *sym_process_group_create(long process_id) {
    HANDLE job;
    HANDLE process;
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;

    job = CreateJobObjectW(NULL, NULL);
    if (job == NULL) {
        return NULL;
    }
    ZeroMemory(&limits, sizeof(limits));
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            &limits,
            sizeof(limits))) {
        CloseHandle(job);
        return NULL;
    }
    process = OpenProcess(
        PROCESS_SET_QUOTA | PROCESS_TERMINATE,
        FALSE,
        (DWORD)process_id);
    if (process == NULL) {
        CloseHandle(job);
        return NULL;
    }
    if (!AssignProcessToJobObject(job, process)) {
        CloseHandle(process);
        CloseHandle(job);
        return NULL;
    }
    CloseHandle(process);
    return (void *)job;
}

static int sym_process_group_terminate(void *group_handle, long process_id) {
    (void)process_id;
    return group_handle != NULL &&
        TerminateJobObject((HANDLE)group_handle, (UINT)1) != 0;
}

static int sym_process_group_has_members(void *group_handle, long process_id) {
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
    (void)process_id;
    if (group_handle == NULL) {
        return -1;
    }
    ZeroMemory(&accounting, sizeof(accounting));
    if (!QueryInformationJobObject(
            (HANDLE)group_handle,
            JobObjectBasicAccountingInformation,
            &accounting,
            sizeof(accounting),
            NULL)) {
        return -1;
    }
    return accounting.ActiveProcesses > 0 ? 1 : 0;
}

static void sym_process_group_close(void *group_handle) {
    if (group_handle != NULL) {
        CloseHandle((HANDLE)group_handle);
    }
}

#else
#  include <errno.h>
#  include <signal.h>
#  include <sys/types.h>
#  include <unistd.h>

static void *sym_process_group_create(long process_id) {
	pid_t group_id;
	int set_group_error;
	if (process_id <= 0) {
		return NULL;
	}
	/* The Eiffel process library also calls setpgid(0, 0) in the child, but
	 * the parent may return from launch before that child-side call runs.
	 * Setting it from the parent closes that scheduling race. If the child
	 * already exec'd, verification below accepts the group it established. */
	if (setpgid((pid_t)process_id, (pid_t)process_id) == 0) {
		return (void *)1;
	}
	set_group_error = errno;
	if (set_group_error != EACCES) {
		return NULL;
	}
	errno = 0;
	group_id = getpgid((pid_t)process_id);
	return group_id == (pid_t)process_id ? (void *)1 : NULL;
}

static int sym_process_group_terminate(void *group_handle, long process_id) {
    int result;
    (void)group_handle;
    if (process_id <= 0) {
        return 0;
    }
    errno = 0;
    result = kill((pid_t)-process_id, SIGKILL);
    return result == 0 || errno == ESRCH;
}

static int sym_process_group_has_members(void *group_handle, long process_id) {
    int result;
    (void)group_handle;
    if (process_id <= 0) {
        return -1;
    }
    errno = 0;
    result = kill((pid_t)-process_id, 0);
    if (result == 0 || errno == EPERM) {
        return 1;
    }
    return errno == ESRCH ? 0 : -1;
}

static void sym_process_group_close(void *group_handle) {
    (void)group_handle;
}
#endif

#endif
