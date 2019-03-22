#!/usr/bin/env bash

# This test compares "known good" output with various settings against output
# with the current code. It's brittle by nature, but this is probably the
# "best" approach possible.
#
# Notes:
# * options passed to this script (such as -v) are ignored, as they would change
#   the output and break the test
# * the number of asterisks after a "banner" differs depending on the number of
#   columns on the TTY, so we must adjust the columns for the current session
#   for consistency

set -eux

run_test() {
	local testname=$1

	# The shenanigans with redirection and 'tee' are to capture STDOUT and
	# STDERR separately while still displaying both to the console
	{ ansible-playbook -i inventory test.yml \
		> >(set +x; tee "${OUTFILE}.${testname}.stdout"); } \
		2> >(set +x; tee "${OUTFILE}.${testname}.stderr" >&2)
	diff -u "${ORIGFILE}.${testname}.stdout" "${OUTFILE}.${testname}.stdout" || diff_failure
	diff -u "${ORIGFILE}.${testname}.stderr" "${OUTFILE}.${testname}.stderr" || diff_failure
}

diff_failure() {
	if [[ $INIT = 0 ]]; then
		echo "FAILURE...diff mismatch!"
		exit 1
	fi
}

cleanup() {
	if [[ $INIT = 0 ]]; then
		rm -rf "${OUTFILE}.*"
	fi

	if [[ -f "${BASEFILE}.unreachable.stdout" ]]; then
	    rm -rf "${BASEFILE}.unreachable.stdout"
	fi

	if [[ -f "${BASEFILE}.unreachable.stderr" ]]; then
	    rm -rf "${BASEFILE}.unreachable.stderr"
	fi

	# Restore TTY cols
	if [[ -n ${TTY_COLS:-} ]]; then
		stty cols "${TTY_COLS}"
	fi
}

adjust_tty_cols() {
	if [[ -t 1 ]]; then
		# Preserve existing TTY cols
		TTY_COLS=$( stty -a | grep -Eo '; columns [0-9]+;' | cut -d';' -f2 | cut -d' ' -f3 )
		# Override TTY cols to make comparing ansible-playbook output easier
		# This value matches the default in the code when there is no TTY
		stty cols 79
	fi
}

BASEFILE=callback_default.out

ORIGFILE="${BASEFILE}"
OUTFILE="${BASEFILE}.new"

trap 'cleanup' EXIT

# The --init flag will (re)generate the "good" output files used by the tests
INIT=0
if [[ ${1:-} == "--init" ]]; then
	shift
	OUTFILE=$ORIGFILE
	INIT=1
fi

adjust_tty_cols

# Force the 'default' callback plugin, since that's what we're testing
export ANSIBLE_STDOUT_CALLBACK=default
# Disable color in output for consistency
export ANSIBLE_FORCE_COLOR=0
export ANSIBLE_NOCOLOR=1

# Default settings
export ANSIBLE_DISPLAY_SKIPPED_HOSTS=1
export ANSIBLE_DISPLAY_OK_HOSTS=1
export ANSIBLE_DISPLAY_FAILED_STDERR=0

run_test default

# Hide skipped
export ANSIBLE_DISPLAY_SKIPPED_HOSTS=0

run_test hide_skipped

# Hide skipped/ok
export ANSIBLE_DISPLAY_SKIPPED_HOSTS=0
export ANSIBLE_DISPLAY_OK_HOSTS=0

run_test hide_skipped_ok

# Hide ok
export ANSIBLE_DISPLAY_SKIPPED_HOSTS=1
export ANSIBLE_DISPLAY_OK_HOSTS=0

run_test hide_ok

# Failed to stderr
export ANSIBLE_DISPLAY_SKIPPED_HOSTS=1
export ANSIBLE_DISPLAY_OK_HOSTS=1
export ANSIBLE_DISPLAY_FAILED_STDERR=1

run_test failed_to_stderr

# Default settings with unreachable tasks
export ANSIBLE_DISPLAY_SKIPPED_HOSTS=1
export ANSIBLE_DISPLAY_OK_HOSTS=1
export ANSIBLE_DISPLAY_FAILED_STDERR=1

# Check if UNREACHBLE is available in stderr
set +e
ansible-playbook -i inventory test_2.yml > >(set +x; tee "${BASEFILE}.unreachable.stdout";) 2> >(set +x; tee "${BASEFILE}.unreachable.stderr" >&2) || true
set -e
if test "$(grep -c 'UNREACHABLE' "${BASEFILE}.unreachable.stderr")" -ne 1; then
    echo "Test failed"
    exit 1
fi
