#!/bin/bash

# Initialize the array for rest of the arguments
rest_of_args=()

# parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--timestamp)
      timestamp="$2"
      shift # past argument
      shift # past value
      ;;
    --clean)
      clean=true
      shift # past argument
      ;;
    *)
      rest_of_args+=("$1") # store rest of arguments
      shift
      ;;
  esac
done

# Generate the output directory with timestamp
if [ -z "$timestamp" ]; then
    timestamp=$(date +"%Y-%m-%d")
fi
output=./reports/BY_DATE/$timestamp
export METTALOG_OUTPUT=$(realpath $output)
export SHARED_UNITS=$METTALOG_OUTPUT/SHARED.UNITS

mkdir -p $output
touch $SHARED_UNITS

echo "Running nightly tests to $output ($METTALOG_OUTPUT) with SHARED_UNITS=$SHARED_UNITS"

source ./scripts/ensure_venv

# Check if 'ansi2html' is already installed
if ! python3 -m pip list | grep -q 'ansi2html'; then
    # Install 'ansi2html' if it is not installed
    python3 -m pip install ansi2html
fi

# This function runs MettaLog tests with configurable output suppression
run_mettalog_tests() {
    local max_time_per_test="$1"
    local test_dir="$2"
    shift 2  # Shift the first two arguments so the rest can be captured as additional arguments
    local args=("$@")
    local status=666

    # Construct the command using an array to handle spaces and special characters properly
    local cmd=(mettalog --output="$output" --test --timeout=$max_time_per_test "$test_dir")
    cmd+=("${args[@]}")
    cmd+=("${rest_of_args[@]}")

    # Optionally remove --clean from subsequent runs
    if [ "$clean" == true ]; then
        cmd+=("--clean")
        clean=false  # Reset or remove the clean option after using it
    fi

    local SHOW_ALL_OUTPUT=true # Set to false normally, true for debugging

    if [ "$SHOW_ALL_OUTPUT" ]; then
        # Execute the command and capture the status
        "${cmd[@]}"
        local status=$?
    else
        # Execute the command silently and filter output, capturing status
        script -q -c "${cmd[*]}" /dev/null | tee >(grep -Ei --line-buffered '_CMD:|es[:] ' >&2) > /dev/null
        local status=$?
    fi

    if [ $status -eq 4 ]; then
	echo "Something purposely interupted testing... results will not be written!"
	# exit $status # exit this script
    fi

    return $status
}


# Actual test calls and logic to manage test conditions
SKIP_LONG=0

# Construct the TEST_CMD string
#TEST_CMD="mettalog --output=$METTALOG_OUTPUT --timeout=$METTALOG_MAX_TIME --html --repl=false ${extra_args[*]} ${passed_along_to_mettalog[*]} \"$file\" --halt=true"

# Call the function with the constructed command and other variables
#IF_REALLY_DO return run_single_timed_unit "$TEST_CMD" "$file_html" "$file" "Under $METTALOG_MAX_TIME seconds"

# 23+ tests (~30 seconds)
run_mettalog_tests 40 tests/baseline_compat/module-system/

# 200+ tests (~4 minutes)
run_mettalog_tests 40 tests/baseline_compat/hyperon-experimental_scripts/
run_mettalog_tests 40 tests/baseline_compat/hyperon-mettalog_sanity/

# 50+ tests (~2 minutes)
run_mettalog_tests 40 tests/baseline_compat/metta-morph_tests/

# Check if SKIP_LONG is not set to 1
if [ "$SKIP_LONG" != "1" ]; then

    # 50+ tests (~2 minutes)
    run_mettalog_tests 40 tests/baseline_compat/anti-regression/

    # 400+ tests (~7 minutes)
    run_mettalog_tests 40 tests/baseline_compat/


    run_mettalog_tests 40 tests/nars_interp/

    run_mettalog_tests 40 tests/more-anti-regression/

    run_mettalog_tests 40 tests/extended_compat/metta-examples/
    run_mettalog_tests 40 tests/extended_compat/

    run_mettalog_tests 40 tests/direct_comp/
    run_mettalog_tests 40 tests/features/
    run_mettalog_tests 40 tests/performance/

  # compiler based tests
    #run_mettalog_tests 40 tests/compiler_baseline/
    #run_mettalog_tests 40 tests/nars_w_comp/
    # run_mettalog_tests 40 tests/python_compat/
fi

cat $SHARED_UNITS > /tmp/SHARED.UNITS

# if ran locally on our systme we might want to commit these
cat /tmp/SHARED.UNITS > ./reports/SHARED.UNITS.PREV.md
