%% tests/test_vetusiapl2webpl.pl
%%
%% Unit tests for the vetusiapl2webpl converter.
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt tests/test_vetusiapl2webpl.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_vetusiapl2webpl].
%%   ?- run_tests.

:- use_module('../src/vetusiapl2webpl').
:- use_module(library(plunit)).
:- use_module(library(lists)).

% Capture the directory of this test file at load time so the
% integration test can find sibling files reliably.
:- prolog_load_context(directory, TestDir),
   assert(test_directory(TestDir)).

% ==========================================================================
% Helpers
% ==========================================================================

%% lines_contain(+Lines, +Sub)
%  True when at least one line in Lines contains the sub-string Sub.
lines_contain(Lines, Sub) :-
    member(Line, Lines),
    sub_atom(Line, _, _, _, Sub), !.

% ==========================================================================
% Tests: internal predicates
% ==========================================================================

:- begin_tests(conjunction_to_list).

test(single_goal) :-
    vetusiapl2webpl:conjunction_to_list(writeln(hello), [writeln(hello)]).

test(two_goals) :-
    vetusiapl2webpl:conjunction_to_list((a, b), [a, b]).

test(three_goals) :-
    vetusiapl2webpl:conjunction_to_list((a, b, c), [a, b, c]).

test(true_is_empty) :-
    vetusiapl2webpl:conjunction_to_list(true, []).

test(nested) :-
    vetusiapl2webpl:conjunction_to_list(((a, b), c), [a, b, c]).

:- end_tests(conjunction_to_list).

% --------------------------------------------------------------------------

:- begin_tests(var_name_of).

test(found) :-
    V = _,
    vetusiapl2webpl:var_name_of(V, ['Foo' = V, 'Bar' = _], 'Foo').

test(second_entry) :-
    A = _, B = _,
    vetusiapl2webpl:var_name_of(B, ['Foo' = A, 'Bar' = B], 'Bar').

test(not_found_returns_anon) :-
    V = _,
    vetusiapl2webpl:var_name_of(V, [], anon).

:- end_tests(var_name_of).

% --------------------------------------------------------------------------

:- begin_tests(split_at_reads).

test(no_reads) :-
    Goals = [writeln(hello), nl],
    vetusiapl2webpl:split_at_reads(Goals, [], Segs),
    Segs = [seg([writeln(hello), nl], none)].

test(one_read) :-
    V = _,
    Goals = [writeln(prompt), read_string(user, "\n", "\r", _, V), writeln(done)],
    VN = ['X' = V],
    vetusiapl2webpl:split_at_reads(Goals, VN, Segs),
    Segs = [seg([writeln(prompt)], 'X'), seg([writeln(done)], none)].

test(two_reads) :-
    V1 = _, V2 = _,
    Goals = [writeln(p1), read_string(user, "\n", "\r", _, V1),
             writeln(p2), read_string(user, "\n", "\r", _, V2),
             writeln(done)],
    VN = ['A' = V1, 'B' = V2],
    vetusiapl2webpl:split_at_reads(Goals, VN, Segs),
    Segs = [seg([writeln(p1)], 'A'),
            seg([writeln(p2)], 'B'),
            seg([writeln(done)], none)].

:- end_tests(split_at_reads).

% --------------------------------------------------------------------------

:- begin_tests(annotate_accumulated).

test(empty) :-
    vetusiapl2webpl:annotate_accumulated([], [], []).

test(single_none_segment) :-
    vetusiapl2webpl:annotate_accumulated(
        [seg([g1], none)], [],
        [seg([g1], none, [])]).

test(two_segments) :-
    vetusiapl2webpl:annotate_accumulated(
        [seg([g1], 'X'), seg([g2], none)], [],
        [seg([g1], 'X', []), seg([g2], none, ['X'])]).

test(three_segments) :-
    vetusiapl2webpl:annotate_accumulated(
        [seg([g1], 'A'), seg([g2], 'B'), seg([g3], none)], [],
        [seg([g1], 'A', []),
         seg([g2], 'B', ['A']),
         seg([g3], none, ['B', 'A'])]).

:- end_tests(annotate_accumulated).

% --------------------------------------------------------------------------

:- begin_tests(is_output_goal).

test(writeln)   :- vetusiapl2webpl:is_output_goal(writeln(hello)).
test(write)     :- vetusiapl2webpl:is_output_goal(write(hello)).
test(nl)        :- vetusiapl2webpl:is_output_goal(nl).
test(format2)   :- vetusiapl2webpl:is_output_goal(format("~w", [x])).
test(format1)   :- vetusiapl2webpl:is_output_goal(format("hello")).
test(print)     :- vetusiapl2webpl:is_output_goal(print(x)).

test(not_output, [fail]) :-
    vetusiapl2webpl:is_output_goal(assert(foo)).

:- end_tests(is_output_goal).

% --------------------------------------------------------------------------

:- begin_tests(goal_to_html_term).

test(writeln_becomes_p) :-
    vetusiapl2webpl:goal_to_html_term(writeln(hello), p(hello)).

test(write_becomes_span) :-
    vetusiapl2webpl:goal_to_html_term(write(hello), span(hello)).

test(nl_becomes_br) :-
    vetusiapl2webpl:goal_to_html_term(nl, br([])).

test(print_becomes_p) :-
    vetusiapl2webpl:goal_to_html_term(print(x), p(x)).

:- end_tests(goal_to_html_term).

% ==========================================================================
% Integration test: end-to-end conversion
% ==========================================================================

:- begin_tests(convert_integration).

%% Perform the full conversion of examples/input_example.pl and check
%% that the output file contains the expected structural elements.
test(full_conversion) :-
    % test_directory/1 is asserted at module load time, pointing to tests/
    test_directory(TestDir),
    file_directory_name(TestDir, RepoRoot),
    atomic_list_concat([RepoRoot, '/examples/input_example.pl'], InputFile),
    % Create a temporary output file and ensure it is deleted afterwards,
    % even if the test fails or throws an exception.
    tmp_file_stream(text, TmpFile, TmpStream),
    close(TmpStream),
    setup_call_cleanup(
        true,
        run_conversion_assertions(InputFile, TmpFile),
        ( exists_file(TmpFile) -> delete_file(TmpFile) ; true )
    ), !.

run_conversion_assertions(InputFile, TmpFile) :-
    % Run the conversion
    convert(InputFile, TmpFile),
    % Read the output file line by line
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    % Structural checks
    lines_contain(Lines, 'http_handler'),    % handler declarations
    lines_contain(Lines, 'step_0('),         % step_0 handler
    lines_contain(Lines, 'step_1('),         % step_1 handler (first read_string)
    lines_contain(Lines, 'step_2('),         % step_2 handler (second read_string)
    lines_contain(Lines, 'use_module'),      % HTTP library imports
    lines_contain(Lines, 'http_server'),     % server startup
    lines_contain(Lines, 'http_parameters'),% parameter extraction
    lines_contain(Lines, 'reply_html_page'),% HTML form reply
    lines_contain(Lines, "'/step_1'"),       % form action for step 1
    lines_contain(Lines, "'/step_2'"),       % form action for step 2
    lines_contain(Lines, "'Name'").          % Name variable threaded forward

read_all_lines(S, Lines) :-
    read_line_to_string(S, Line),
    ( Line == end_of_file ->
        Lines = []
    ;   atom_string(LineAtom, Line),
        Lines = [LineAtom | Rest],
        read_all_lines(S, Rest)
    ).

:- end_tests(convert_integration).
