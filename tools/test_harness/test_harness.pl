:-module(test_harness, [result_code_extension/3
                       ,generate_answers/3
                       ,run_failed_tests/3
                       ,run_timed_out/3
                       ,new_file_extension/4
                       ,deleted_file/2
                       ,renamed_file/3
                       ,copied_file/3
                       ]).

/** <module> Run metta test scripts and generate answers files.

This module implements a rudimentary test harness for metta tests.
Predicates defined here execute metta test scripts and write out files
containing their outputs.

We refer to files with test script outputs as answer files. Predicates
in this module write out answers files with an extension denoting
success or failure of the corresponding tests. Tests are mainly run with
a timeout (via the linux timeout command) and so the main way that a
test will fail is by timing out. Unfortunately metta does not return a
shell status code indicating success or failure that can be used to
determine whether a test really-really succeed (passed) or failed so the
only thing we can do is capture shell status codes that indicate the way
that the metta command itself (rather than a test) terminated.

Some high-level information about predicates exported by this module:

generate_answers/2
------------------

Runs metta tests in a directory and generates answers files, including
for timed-out and otherwise error'd tests. Takes a timeout parameter.

Example call:
==
?- _Dir='test-suite/nars_w_comp/nars/main-branch', generate_answers(run,_Dir,1).
==

The query above will run all tests in _Dir with a timeout of 1 second
(passed to the shell timeout command) and write out answers files, with
an extension denoting the result. The first argument, "run" indicates
that files will be written normally; alternatively, if the same query is
made with "dry_run" as the first argument, no files will be written.


run_timed_out/2
---------------

Finds and re-runs timed-out tests in a directory,
possibly with an increased timeout parameter. Deletes existing timeout
files first.

Example call:
==
?- _Dir='test-suite/nars_w_comp/nars/main-branch', run_timed_out(run,_Dir,'1m').
==

The query above will run timed-out tests in _Dir, with a timeout of 1
minute (passed to the timeout shell command). The first argument, "run"
indicates that tests will be run normally, beginning by deleting
existing timeout files.


Keeping a record of test running times
--------------------------------------

The time (CPU and wall-clock) taken to run each test is recorded in a
separate file, in the path determined by time_file/1. We call this file
the "time file".

Depending on the value of time_file_init/1 the time file can either be
cleared or its contents can be updated incrementally every time tests
are run.

Examples:

1. The time file will be written in the file test_times.log, in the
SWI-Prolog current working directory. The time file will be updated by
appending new entries at the end, preserving existing entries.

==
time_file('test_times.log').

time_file_init(update).
==

2. The time file will be written to
/home/metta/metta-wam/test_times.log. The time file will be updated by
clearing its contents before writing new entries.

==
time_file('/home/metta/metta-wam/test_times.log').

time_file_init(reset).
==

*/

% Set and reset top-level logging for each known debug subject.
%
% Uncomment only first directive to turn off logging
% Uncomment each other directive to turn on logging for the
% corresponding subject.
:-nodebug(_).
:-debug(run_timed_out).
:-debug(deleted_file).
:-debug(run_tests).
:-debug(exec_command).
:-debug(was_answers_file_written).
:-debug(shell_code_action).
:-debug(renamed_file).
:-debug(copied_file).


%!      clobber(?Bool) is semidet.
%
%       Whether to clobber existing answers files or not.
%
%       If Bool is true, tests for metta files with an existing answers
%       are not run at all.
%
clobber(false).


%!      test_file_extension(?Extension) is semidet.
%
%       Filename Extension of metta test files.
%
%       This will normally be ".metta", although Extension should just
%       be the part after the '.'.
%
test_file_extension(metta).


%!      time_file(?Path) is semidet.
%
%       Path to the file holding test running times.
%
%       Path can be either an absolute path or a path relative to the
%       SWI-Prolog current directory.
%
time_file('test_times.log').


%!      time_file_init(?Mode) is semidet.
%
%       How to update the time file when restting it.
%
%       Mode is one of: [reset,update]. Mode "reset" clears the file
%       and restarts from the top. Mode "update" continues from the
%       last line without clearing the file.
%
time_file_init(update).
%time_file_init(reset).



%!      metta_command(?Mode,?Cmd) is semidet.
%
%       The bash command to run the metta compiler.
%
%       Mode is an atom that describes the mode in which the command
%       should be run, currently one of: [run, dry_run]. Those are
%       interpreted as follows:
%       * Mode "run" runs the command normally and generates an output
%       file.
%       * Mode "dry_run" runs the command normally but does not
%       generate any output files.
%
%       Running in dry_run mode may not always be sensible e.g.
%       predicates like run_timed_out/2 re-run tests based on the
%       initial tests' output files, but if those files don't exist,
%       then nothing will run.
%
%       Cmd is a Prolog atom passed as the first argument to format/2 to
%       compose a command send to the Bourne shell. This atom can
%       contain all the special notation accepted by format/2, such as
%       ~w, ~n, ~f etc.
%
metta_command(run,'timeout --foreground --k=5 --s=SIGKILL -v ~w metta "~w" > "~w" 2>&1').
% ~i ignores the argument in that position.
metta_command(dry_run,'timeout --foreground --k=5 --s=SIGKILL -v ~w metta "~w" 2>&1 ~i').


%!      result_code_extension(?Result,?Code,?Extension) is semidet.
%
%       Mapping between test results, exit codes and file extensions.
%
%       Used to determine the extension of a file generated by
%       test-running predicates, possibly containing test results, or
%       errors etc, and any suffixes indicating the result.
%
%       The mapping between results, codes and file extensions is as
%       follows:
%
%       Test result    Exit Code   Extension
%       Success        0           .metta.answers
%       Timeout        1           .metta.error
%       Timeout        124         .metta.timeout
%       Aborted        134         .metta.aborted
%       Killed         137         .metta.SIGKILLED
%
%       Note that in the Extensions below, only the one for a successful
%       test result has a "metta." extension prefix. That's fine. For
%       other test results the given Extension is added as a suffix to
%       .metta. If you want to changet that, remove the 'metta.' prefix
%       from the success clause.
%
result_code_extension(success,0,'metta.answers').
result_code_extension(error,1,'unknown_error').
result_code_extension(timeout,124,'timeout').
result_code_extension(abort,134,'aborted').
result_code_extension(kill,137,'SIGKILLED').
result_code_extension(test_error,nil,'test_error').


%!      generate_answers(+Mode,+Directory,+Timeout) is det.
%
%       Generate test answers.
%
%       Mode is the mode in which to run the metta command, used to
%       select clauses of metta_command/2. Options are "run" and
%       "dry_run". See metta_command/2 for details.
%
%       Directory is the name of the directory in which test files are
%       to be found.
%
%       Timeout is the atomic timeout passed to the timeout command to
%       run the tests.
%
%       In Mode "run" this predicate will write answers files for all
%       successful tests, timeout files for all timed-out tests, etc.
%       Existing files will be clobbered. In Mode "dry_run", no files
%       will be written, or replaced.
%
generate_answers(R,Dir,T):-
        test_file_extension(E),
        result_code_extension(success,_,S),
        run_tests(R,Dir,T,E,S).


%!      run_failed_tests(+Mode,+Directory,+Timeout) is det.
%
%       Run metta files with a test_error extension.
%
%       Mode is the mode in which to run the metta command, used to
%       select clauses of metta_command/2. Options are "run" and
%       "dry_run". See metta_command/2 for details.
%
%       Directory is the name of the directory in which test files are
%       to be found.
%
%       Timeout is the atomic timeout passed to the timeout command to
%       run the tests.
%
%       This predicate collectst the names of results files with failed
%       tests in the given Directory and passes to run_tests/4 the list
%       of corresponding metta test files to be run again with the given
%       Timeout.
%
%       Files with failed tests get the extension defined in the third
%       argument of result_code_extension/3 where the first argument is
%       test_error. Normally the extension is also test_error.
%
%       Note well: if Mode is "run", this predicate will begin by
%       deleting each test error file in the given Directory. If the
%       same test fails again, a new test error file will be generated.
%       If Mode is "dry_run" no files will be deleted, and no new files
%       generated.
%
run_failed_tests(R,Dir,T):-
        result_code_extension(test_error,_,TO),
        test_file_extension(E),
        result_code_extension(success,_,S),
        findall(F_,
                (directory_member(Dir,F,[recursive(true),
                                         extensions([TO]),
                                         follow_links(true)
                                        ]),
                 deleted_file(R,F),
                 new_file_extension(F,TO,E,F_)
                ),
                Fs),
        run_tests(R,Fs,T,E,S).



%!      run_timed_out(+Mode,+Directory,+Timeout) is det.
%
%       Run timed-out tests in a Directory.
%
%       Mode is the mode in which to run the metta command, used to
%       select clauses of metta_command/2. Options are "run" and
%       "dry_run". See metta_command/2 for details.
%
%       Directory is the name of the directory in which test files are
%       to be found.
%
%       Timeout is the atomic timeout passed to the timeout command to
%       run the tests.
%
%       This predicate collects the names of results file of timed-out
%       tests in the given Directory and passes to run_tests/4 the list
%       of corresponding metta test files, to be run again, with the
%       given Timeout.
%
%       Note well: if Mode is "run", this predicate will begin by
%       deleting each timeout file in the given Directory. If the same
%       test times out again, a new timeout file will be generated,
%       possibly with more output than the original one. If Mode is
%       "dry_run" no files will actually be deleted, and no new files
%       generated.
%
run_timed_out(R,Dir,T):-
        result_code_extension(timeout,_,TO),
        test_file_extension(E),
        result_code_extension(success,_,S),
        findall(F_,
                (directory_member(Dir,F,[recursive(true),
                                         extensions([TO]),
                                         follow_links(true)
                                        ]),
                 deleted_file(R,F),
                 new_file_extension(F,TO,E,F_)
                ),
                Fs),
        run_tests(R,Fs,T,E,S).



%!      run_tests(+Mode,+InFiles,+Timeout,+ExtIn,+ExtOut) is det.
%
%       Run the metta test scripts in a Directory.
%
%       Mode is the mode in which to run the metta command, used to
%       select clauses of metta_command/2. Options are "run" and
%       "dry_run". See metta_command/2 for details.
%
%       InFiles can be either an atomic directory name, or a list of
%       atomic absolute file paths. If InFiles is a directory name, it
%       is taken to be the name of the top-level directory to search for
%       .metta files with tests to be executed.
%
%       Timeout is an atom passed as the DURATION argument to the
%       timeout linux command. This may be a number, including a float,
%       in which case it will be interpreted as a duration in seconds,
%       the default. Otherwise a suffix 's' for seconds, 'm' for
%       minutes, 'h' for hours and 'd' for days can be appended to a
%       numeric value, but the whole argument must remain an atom. For
%       example '10m' is a valid argument, '0.5h' is a valid argument,
%       but 10h is not.
%
%       This predicate runs all the metta test scripts determined by
%       InFiles. If InFiles is a directory name this predicate runs all
%       test secripts in the given directory and all its subdirectories,
%       including over symbolic links (On Linux). In that case Metta
%       test scripts are identified as files with a '.metta' extension.
%
%       The result of running a script is a file with the same name as
%       the test script file, with the suffix '.answers' appended to
%       its file extension and with 0 or more additional suffixes
%       indicating the results of a failed test. Suffixes correspond to
%       the exit code returned by the shell when running the metta
%       command (via the timeout command). Exit codes are mapped to
%       suffixes by result_code_extension/3. See that predicate for more
%       details of the mapping.
%
%       Test scripts are passed to metta via the timeout command using
%       the given Timeout value. The text of the command sent to the
%       bash shell is defined in metta_command/1. See that predicate for
%       more details.
%
run_tests(R,Dir,T,EIn,EOut):-
% When the first argument is a directory.
        atom(Dir),
        !,
        metta_command(R,Cmd),
        init_time_file,
        forall(directory_member(Dir,F,[recursive(true),
                                       extensions([EIn]),
                                       follow_links(true)
                                      ]),
               % Initial name of the file with test output.
               (new_file_extension(F,EIn,EOut,OF),
                exec_command(R,Cmd,T,F,OF)
               )
              ).
run_tests(R,Fs,T,EIn,EOut):-
% When the first argument is a list of file paths.
        is_list(Fs),
        metta_command(R,Cmd),
        forall(member(F,Fs),
               (new_file_extension(F,EIn,EOut,OF),
                exec_command(R,Cmd,T,F,OF)
               )
              ).


%!      exec_command(+Mode,+Command,+Timeout,+Test,+Answers) is det.
%
%       Execute a shell Command to run tests and generate answers files.
%
%       Mode is one of "run" and "dry_run". See metta_command/2 for
%       details.
%
%       Command is the command to be run, taken from the second argument
%       of metta_command/2.
%
%       Timeout is sent to the timeout shell command to run Command
%       with a timeout.
%
%       Test is the full atomic path of the metta test script to run
%       with Command.
%
%       Answers is the full atomic path of the answers file with the
%       output of running the script in Test with Command. Answers may
%       be further renamed by shell_code_action/3.
%
%       This is the business end of run_tests/4. Clauses of this
%       predicate are selected according to the value of clobber/1.
%
%       If clobber(false) is set and a file exists with an extension
%       indicating that a metta. test script has already been run, the
%       test script will not run and no new file will be generated.
%
%       If clobber(false) is not set then no check is made that an
%       answers etc file exists already and the test script is run
%       again. In that case, the existing file will be clobbered, i.e.
%       its contents completely replaced by the output of the new run of
%       the test script.
%
exec_command(_R,_Cmd,_T,_TF,AF):-
        clobber(false),
        result_code_extension(_,C,Ext),
        C \== 0
        ,new_file_extension(AF,_,Ext,OF),
        debug(exec_command,'clobber(false) Looking for file ~w',[OF]),
        (   exists_file(OF)
        ->  EF = OF
        ;   exists_file(AF),
            debug(exec_command,'clobber(false) Looking for file ~w',[AF])
        ->  EF = AF
        ;   fail
        ),
        !,
        debug(exec_command,'~w exists and clobber(false): Not running test',[EF]).
exec_command(R,Cmd,T,TF,AF):-
        % C is the shell command with input and output file names.
        format(atom(C),Cmd,[T,TF,AF]),
        debug(exec_command,'Running test ~w',[TF]),
        %shell(C,S),
        call_time(shell(C,S),Tm),
        write_time_file(TF,Tm),
        debug(exec_command,'Shell command exited with status ~w',[S]),
        was_answers_file_written(AF),
        % Depending on status code the output file may be renamed in place.
        shell_code_action(R,S,AF),
        ttyflush.


%!      was_answer_file_written(+AnswersFile) is det.
%
%       Check that an Answers file was written and report it.
%
%       Helper to log whether an answers file was written as a result of
%       attempgint to run a metta test script, or not.
%
was_answers_file_written(AF):-
        \+ exists_file(AF),
        !,
        debug(was_answers_file_written,'Answers file ~w was not written',[AF]).
was_answers_file_written(AF):-
        debug(was_answers_file_written,'Wrote answers file ~w',[AF]).


%!      shell_code_action(+Mode,+Code,+File) is det.
%
%       Determines the Action to take on a shell exit Code.
%
%       Helper to run_tests/4 used to rename answers files with
%       suffixes indicating the result of running the test, if needed.
%
%       Mode is the mode in which to run the metta command, used to
%       select clauses of metta_command/2. Options are "run" and
%       "dry_run". See metta_command/2 for details.
%
%       Code is the shell status code returned by a shell command,
%       generated by a call to shell/2 in run_tests/5.
%
%       File is the atomic path to a file that may or may not be
%       renamed, depending on Code. Files are renamed with a new
%       extension to indicate the result of the corresponding test.
%       Extensions are define by result_code_extension/3. See that
%       predicate for details.
%
%       The file to be renamed by this predicate must already exist (it
%       will normally be generated by generate_answers/5). If it doesn't
%       this predicate will only output a log message, if
%       shell_code_action is being debugged, and exit without touching
%       the file system.
%
shell_code_action(_R,0,_IF):-
        !.
shell_code_action(R,C,IF):-
        !,
        once( result_code_extension(_,C,S) ),
        new_file_extension(IF,_E,S,OF),
        renamed_file(R,IF,OF).
shell_code_action(R,_,IF):-
        % All other codes go to a generic 'error'
        once( result_code_extension(_,1,S) ),
        new_file_extension(IF,_E,S,OF),
        renamed_file(R,IF,OF).


%!      new_file_extension(+Mode,+Filename,+ExtIn,+ExtOut,-New) is det.
%
%       Replace the extension of a filename with a new one.
%
%       Helper predicate to simplify changing filename extensions.
%
new_file_extension(F,EIn,EOut,F_):-
        file_name_extension(B,EIn,F),
        file_name_extension(B,EOut,F_).


%!      deleted_file(+Mode,+File) is det.
%
%       Delete a File.
%
%       Wrapper around delete_file/1 to manage its behaviour according
%       to Mode.
%
deleted_file(_,IF):-
        \+ exists_file(IF),
        !,
        debug(deleted_file,'Could not delete file ~w because it does not exist',[IF]).
deleted_file(run,F):-
        delete_file(F),
        debug(deleted_file,'Deleting file ~w',[F]).
deleted_file(dry_run,F):-
        debug(deleted_file,'(Dry Run) Deleting file ~w',[F]).


%!      rename_file(+Mode,+InFile,+OutFile) is det.
%
%       Rename a file.
%
%       Wrapper around rename_file/2 to manage its behaviour according
%       to Mode.
%
%       The file to be renamed by this predicate must already exist (it
%       will normally be generated by generate_answers/5). If it doesn't
%       this predicate will only output a log message, if
%       shell_code_action is being debugged, and exit without touching
%       the file system.
%
renamed_file(_,IF,_OF):-
        \+ exists_file(IF),
        !,
        debug(renamed_file,'Could not rename file ~w because it does not exist',[IF]).
renamed_file(run,IF,OF):-
        rename_file(IF,OF),
        debug(renamed_file,'Renamed answers file to ~w',[OF]).
renamed_file(dry_run,_IF,OF):-
        debug(renamed_file,'(Dry Run) Renamed answers file to ~w',[OF]).



%!      copied_file(+Mode,+InFile,+OutFile) is det.
%
%       Rename a file.
%
%       Wrapper around rename_file/2 to manage its behaviour according
%       to Mode.
%
%       The file to be renamed by this predicate must already exist (it
%       will normally be generated by generate_answers/5). If it doesn't
%       this predicate will only output a log message, if
%       shell_code_action is being debugged, and exit without touching
%       the file system.
%
copied_file(_,IF,_OF):-
        \+ exists_file(IF),
        !,
        debug(copied_file,'Could not copy file ~w because it does not exist',[IF]).
copied_file(_,_IF,OF):-
        exists_file(OF),
        !,
        debug(copied_file,'Could not copy to file ~w because it already exists',[OF]).
copied_file(run,IF,OF):-
        copy_file(IF,OF),
        debug(copied_file,'Copied answers file to ~w',[OF]).
copied_file(dry_run,_IF,OF):-
        debug(copied_file,'(Dry Run) Copied answers file to ~w',[OF]).


%!      write_time_file(+TestFile,+TimeFile) is det.
%
%       Write the time it took to run a test to a file.
%
%       Test file is the name of a metta test file.
%
%       TimeFile is the name of the "time file" a file recording the
%       names of test files and the time it took to execute them.
%
%       Timing information is generated by the SWI-Prolog time/2
%       predicate and appended to the time file.
%
write_time_file(TF,T):-
        time_file(F),
        S = open(F,append,Strm,[alias(time_file),
                                close_on_abort(true)
                               ]
                ),
        G = ( format(Strm,'Running tests in file ~w~n',[TF]),
              format(Strm,'CPU time: ~4f Wall clock time: ~4f~n',[T.cpu,T.wall])
            ),
        C = close(Strm),
        setup_call_cleanup(S,G,C).


%!      init_time_file is det.
%
%       Initialise the time file recording test running times.
%
%       If time_file_init(reset) is true, this predicate first clears
%       the contents of the time file, then writes the current date and
%       time in the first line in the file.
%
%       If time_file_init(update) is true, the current contents of the
%       time file are not touched and the current date and time are
%       written in the first new line in the file.
%
init_time_file:-
        time_file(F),
        time_file_init(M),
        (   M == reset
        ->  M_ = write
        ;   M == update
        ->  M_ = append
        ),
        S = open(F,M_,Strm,[alias(time_file),
                           close_on_abort(true)
                          ]
                ),
        G = ( get_time(T),
              format_time(atom(A),'%a, %d %b %Y %T %z',T),
              format(Strm,'Running tests on ~w~n',[A])
            ),
        C = close(Strm),
        setup_call_cleanup(S,G,C).

