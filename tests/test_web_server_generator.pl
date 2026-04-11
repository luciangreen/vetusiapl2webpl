%% tests/test_web_server_generator.pl
%%
%% Unit and integration tests for the Stage 5 web server skeleton generator
%% (src/web_server_generator.pl).
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_web_server_generator.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_web_server_generator].
%%   ?- run_tests.

:- use_module('../src/web_server_generator').
:- use_module('../src/reader').
:- use_module('../src/checkpoint_detector').
:- use_module('../src/continuation_extractor').
:- use_module(library(plunit)).
:- use_module(library(lists)).

% Capture the test directory at load time so integration tests can locate
% sibling files reliably.
:- prolog_load_context(directory, Dir),
   assert(wsg_test_dir(Dir)).

% ==========================================================================
% Helper predicates
% ==========================================================================

%% lines_contain(+Lines, +Sub)
%  True when at least one line in Lines contains the sub-string Sub.
lines_contain(Lines, Sub) :-
    member(Line, Lines),
    sub_atom(Line, _, _, _, Sub), !.

%% read_all_lines(+Stream, -Lines)
%  Read all lines from Stream as a list of atoms.
read_all_lines(S, Lines) :-
    read_line_to_string(S, Line),
    ( Line == end_of_file ->
        Lines = []
    ;   atom_string(LineAtom, Line),
        Lines = [LineAtom | Rest],
        read_all_lines(S, Rest)
    ).

%% run_generate_and_check(+InputFile, +TmpFile, +Port, :Checks)
%  Generate the web server to TmpFile, then run Checks (a goal) on the
%  output lines.  Cleans up TmpFile afterwards.
run_generate_and_check(InputFile, TmpFile, Port, Checks) :-
    ( Port =:= 8080 ->
        generate_web_server(InputFile, TmpFile)
    ;   generate_web_server(InputFile, TmpFile, Port)
    ),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    call(Checks, Lines).

% ==========================================================================
% Tests: wsg_find_main/4
% ==========================================================================

:- begin_tests(wsg_find_main).

test(finds_main_at_head) :-
    NCs = [ norm_clause(main, norm_true, []) ],
    web_server_generator:wsg_find_main(NCs, norm_true, [], []).

test(finds_main_after_directive) :-
    NCs = [ directive(use_module(lists)),
            norm_clause(main, norm_true, ['X'=_]) ],
    web_server_generator:wsg_find_main(NCs, norm_true, ['X'=_], [directive(use_module(lists))]).

test(aux_clauses_preserved) :-
    V = _,
    NCs = [ norm_clause(helper, norm_goal(write(V)), ['V'=V]),
            norm_clause(main, norm_true, []) ],
    web_server_generator:wsg_find_main(NCs,
        norm_true, [],
        [norm_clause(helper, norm_goal(write(V)), ['V'=V])]).

:- end_tests(wsg_find_main).

% ==========================================================================
% Tests: wsg_denormalise_body/2
% ==========================================================================

:- begin_tests(wsg_denormalise_body).

test(norm_true_becomes_true) :-
    web_server_generator:wsg_denormalise_body(norm_true, true).

test(norm_cut_becomes_cut) :-
    web_server_generator:wsg_denormalise_body(norm_cut, !).

test(norm_goal_unwrapped) :-
    web_server_generator:wsg_denormalise_body(norm_goal(assert(foo)), assert(foo)).

test(norm_output_unwrapped) :-
    web_server_generator:wsg_denormalise_body(norm_output(writeln(hi)), writeln(hi)).

test(norm_conj) :-
    web_server_generator:wsg_denormalise_body(
        norm_conj(norm_output(writeln(a)), norm_goal(foo)),
        (writeln(a), foo)).

test(norm_disj) :-
    web_server_generator:wsg_denormalise_body(
        norm_disj(norm_goal(a), norm_goal(b)),
        (a ; b)).

test(norm_if_then) :-
    web_server_generator:wsg_denormalise_body(
        norm_if_then(norm_goal(c), norm_goal(d)),
        (c -> d)).

test(norm_if_then_else) :-
    web_server_generator:wsg_denormalise_body(
        norm_if_then_else(norm_goal(c), norm_goal(t), norm_goal(e)),
        (c -> t ; e)).

test(norm_read_string) :-
    V = _,
    web_server_generator:wsg_denormalise_body(
        norm_read_string(user, "\n", "\r", _, V),
        read_string(user, "\n", "\r", _, V)).

:- end_tests(wsg_denormalise_body).

% ==========================================================================
% Tests: wsg_emit_server_bootstrap/2  (structural check via atom_to_term)
% ==========================================================================

:- begin_tests(wsg_emit_server_bootstrap).

test(default_port_8080) :-
    with_output_to(atom(Out), web_server_generator:wsg_emit_server_bootstrap(current_output, 8080)),
    sub_atom(Out, _, _, _, 'vetusia_server(Port)'),
    sub_atom(Out, _, _, _, 'vetusia_server(8080)'),
    sub_atom(Out, _, _, _, 'http_server(http_dispatch').

test(custom_port_9090) :-
    with_output_to(atom(Out), web_server_generator:wsg_emit_server_bootstrap(current_output, 9090)),
    sub_atom(Out, _, _, _, 'vetusia_server(9090)'),
    sub_atom(Out, _, _, _, 'vetusia_server(Port)').

test(initialization_directive_present) :-
    with_output_to(atom(Out), web_server_generator:wsg_emit_server_bootstrap(current_output, 8080)),
    sub_atom(Out, _, _, _, 'initialization(main, main)').

:- end_tests(wsg_emit_server_bootstrap).

% ==========================================================================
% Tests: wsg_emit_use_modules/1
% ==========================================================================

:- begin_tests(wsg_emit_use_modules).

test(all_required_libraries_present) :-
    with_output_to(atom(Out), web_server_generator:wsg_emit_use_modules(current_output)),
    sub_atom(Out, _, _, _, 'thread_httpd'),
    sub_atom(Out, _, _, _, 'http_dispatch'),
    sub_atom(Out, _, _, _, 'html_write'),
    sub_atom(Out, _, _, _, 'http_parameters'),
    sub_atom(Out, _, _, _, 'http_header').

:- end_tests(wsg_emit_use_modules).

% ==========================================================================
% Tests: wsg_emit_handler_decls/2
% ==========================================================================

:- begin_tests(wsg_emit_handler_decls).

test(root_handler_always_present) :-
    with_output_to(atom(Out),
        web_server_generator:wsg_emit_handler_decls(current_output, [])),
    sub_atom(Out, _, _, _, 'http_handler(root(.)').

test(post_handler_for_step_1) :-
    Steps = [ cont_step(step_0, [], [], result_resp([], [])),
              cont_step(step_1, ['X'], [], result_resp([], ['X'])) ],
    with_output_to(atom(Out),
        web_server_generator:wsg_emit_handler_decls(current_output, Steps)),
    sub_atom(Out, _, _, _, 'http_handler(root(step_1)'),
    sub_atom(Out, _, _, _, 'method(post)').

test(step_0_not_repeated_as_post) :-
    Steps = [ cont_step(step_0, [], [], result_resp([], [])) ],
    with_output_to(atom(Out),
        web_server_generator:wsg_emit_handler_decls(current_output, Steps)),
    \+ sub_atom(Out, _, _, _, 'method(post)').

:- end_tests(wsg_emit_handler_decls).

% ==========================================================================
% Integration test: generate_web_server/2 with input_example.pl
% ==========================================================================

:- begin_tests(generate_web_server_integration).

test(input_example_default_port, [
        setup(tmp_file_stream(text, TmpFile, TmpStream)),
        cleanup( ( exists_file(TmpFile) -> delete_file(TmpFile) ; true ) )
    ]) :-
    close(TmpStream),
    wsg_test_dir(TestDir),
    file_directory_name(TestDir, RepoRoot),
    atomic_list_concat([RepoRoot, '/examples/input_example.pl'], InputFile),
    generate_web_server(InputFile, TmpFile),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    % HTTP library imports
    lines_contain(Lines, 'thread_httpd'),
    lines_contain(Lines, 'http_dispatch'),
    lines_contain(Lines, 'html_write'),
    lines_contain(Lines, 'http_parameters'),
    lines_contain(Lines, 'http_header'),
    % Handler declarations
    lines_contain(Lines, 'http_handler'),
    % vetusia_server/1 entry predicate
    lines_contain(Lines, 'vetusia_server(Port)'),
    lines_contain(Lines, 'http_server(http_dispatch'),
    % main/0 calls vetusia_server with port
    lines_contain(Lines, 'vetusia_server(8080)'),
    % initialization directive
    lines_contain(Lines, 'initialization(main, main)'),
    % Step handlers
    lines_contain(Lines, 'step_0('),
    lines_contain(Lines, 'step_1('),
    lines_contain(Lines, 'step_2('),
    % html reply
    lines_contain(Lines, 'reply_html_page'),
    % form action targets
    lines_contain(Lines, '/step_1'),
    lines_contain(Lines, '/step_2').

test(input_example_custom_port, [
        setup(tmp_file_stream(text, TmpFile, TmpStream)),
        cleanup( ( exists_file(TmpFile) -> delete_file(TmpFile) ; true ) )
    ]) :-
    close(TmpStream),
    wsg_test_dir(TestDir),
    file_directory_name(TestDir, RepoRoot),
    atomic_list_concat([RepoRoot, '/examples/input_example.pl'], InputFile),
    generate_web_server(InputFile, TmpFile, 9090),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    % Custom port in main/0
    lines_contain(Lines, 'vetusia_server(9090)'),
    % vetusia_server/1 still present
    lines_contain(Lines, 'vetusia_server(Port)').

:- end_tests(generate_web_server_integration).

% ==========================================================================
% Integration test: generate_web_server/2 with auth_example.pl
% ==========================================================================

:- begin_tests(generate_web_server_auth_integration).

test(auth_example_branching, [
        setup(tmp_file_stream(text, TmpFile, TmpStream)),
        cleanup( ( exists_file(TmpFile) -> delete_file(TmpFile) ; true ) )
    ]) :-
    close(TmpStream),
    wsg_test_dir(TestDir),
    file_directory_name(TestDir, RepoRoot),
    atomic_list_concat([RepoRoot, '/examples/auth_example.pl'], InputFile),
    generate_web_server(InputFile, TmpFile),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    % Basic boilerplate
    lines_contain(Lines, 'vetusia_server(Port)'),
    lines_contain(Lines, 'vetusia_server(8080)'),
    lines_contain(Lines, 'http_handler'),
    % Multiple step handlers generated for branching flow
    lines_contain(Lines, 'step_0('),
    lines_contain(Lines, 'step_1(').

:- end_tests(generate_web_server_auth_integration).
