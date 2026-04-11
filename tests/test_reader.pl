%% tests/test_reader.pl
%%
%% Unit and integration tests for the Stage 2 reader module (src/reader.pl).
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_reader.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_reader].
%%   ?- run_tests.

:- use_module('../src/reader').
:- use_module(library(plunit)).
:- use_module(library(lists)).

% Capture the directory of this test file at load time so integration
% tests can locate sibling files reliably.
:- prolog_load_context(directory, Dir),
   assert(reader_test_dir(Dir)).

% ==========================================================================
% Tests: normalise_body/2
% ==========================================================================

:- begin_tests(normalise_body).

test(true_stays_norm_true) :-
    reader:normalise_body(true, norm_true).

test(cut_becomes_norm_cut) :-
    reader:normalise_body(!, norm_cut).

test(conjunction) :-
    reader:normalise_body((a, b),
        norm_conj(norm_goal(a), norm_goal(b))).

test(nested_conjunction) :-
    reader:normalise_body((a, b, c),
        norm_conj(norm_goal(a), norm_conj(norm_goal(b), norm_goal(c)))).

test(disjunction) :-
    reader:normalise_body((a ; b),
        norm_disj(norm_goal(a), norm_goal(b))).

test(if_then) :-
    reader:normalise_body((a -> b),
        norm_if_then(norm_goal(a), norm_goal(b))).

test(if_then_else) :-
    reader:normalise_body((a -> b ; c),
        norm_if_then_else(norm_goal(a), norm_goal(b), norm_goal(c))).

test(if_then_else_not_a_plain_disj) :-
    % (Cond -> Then ; Else) must be recognised before bare disjunction
    reader:normalise_body((x -> y ; z), norm_if_then_else(_, _, _)).

test(read_string_5) :-
    reader:normalise_body(read_string(user, "\n", "\r", _, V),
        norm_read_string(user, "\n", "\r", _, V)).

test(read_password_2) :-
    reader:normalise_body(read_password('Password: ', P),
        norm_read_password('Password: ', P)).

test(read_password_1) :-
    reader:normalise_body(read_password(P),
        norm_read_password(P)).

test(writeln_is_output) :-
    reader:normalise_body(writeln(hello), norm_output(writeln(hello))).

test(write_is_output) :-
    reader:normalise_body(write(hello), norm_output(write(hello))).

test(nl_is_output) :-
    reader:normalise_body(nl, norm_output(nl)).

test(format2_is_output) :-
    reader:normalise_body(format("~w~n", [x]), norm_output(format("~w~n", [x]))).

test(format1_is_output) :-
    reader:normalise_body(format("hello~n"), norm_output(format("hello~n"))).

test(print_is_output) :-
    reader:normalise_body(print(x), norm_output(print(x))).

test(writef_is_output) :-
    reader:normalise_body(writef("hello ~w", [x]), norm_output(writef("hello ~w", [x]))).

test(other_goal) :-
    reader:normalise_body(assert(foo), norm_goal(assert(foo))).

test(nested_if_then_else_in_conj) :-
    reader:normalise_body((a, (b -> c ; d)),
        norm_conj(norm_goal(a),
                  norm_if_then_else(norm_goal(b), norm_goal(c), norm_goal(d)))).

:- end_tests(normalise_body).

% ==========================================================================
% Tests: normalise_clause/3
% ==========================================================================

:- begin_tests(normalise_clause).

test(fact_becomes_norm_clause_with_norm_true) :-
    reader:normalise_clause(foo, [], norm_clause(foo, norm_true, [])).

test(rule_body_is_normalised) :-
    reader:normalise_clause((foo :- bar), [],
        norm_clause(foo, norm_goal(bar), [])).

test(rule_with_conjunction_body) :-
    reader:normalise_clause((foo :- (a, b)), [],
        norm_clause(foo, norm_conj(norm_goal(a), norm_goal(b)), [])).

test(directive_is_tagged) :-
    reader:normalise_clause((:- use_module(lib)), [],
        directive(use_module(lib))).

test(var_names_preserved) :-
    V = _,
    VN = ['X' = V],
    reader:normalise_clause((foo :- writeln(V)), VN,
        norm_clause(foo, norm_output(writeln(V)), VN)).

:- end_tests(normalise_clause).

% ==========================================================================
% Tests: is_output_goal/1
% ==========================================================================

:- begin_tests(reader_is_output_goal).

test(writeln)   :- reader:is_output_goal(writeln(hello)).
test(write)     :- reader:is_output_goal(write(hello)).
test(nl)        :- reader:is_output_goal(nl).
test(format2)   :- reader:is_output_goal(format("~w", [x])).
test(format1)   :- reader:is_output_goal(format("hello")).
test(print)     :- reader:is_output_goal(print(x)).

test(not_output, [fail]) :-
    reader:is_output_goal(assert(foo)).

:- end_tests(reader_is_output_goal).

% ==========================================================================
% Integration test: read_and_normalise/2 on examples/input_example.pl
% ==========================================================================

:- begin_tests(read_and_normalise).

%% Parse the sample input file and verify the overall structure.
test(input_example_parses) :-
    input_file(File),
    reader:read_and_normalise(File, NormClauses),
    NormClauses \= [].

%% The file must contain at least one directive.
test(contains_directive) :-
    input_file(File),
    reader:read_and_normalise(File, NormClauses),
    once(member(directive(_), NormClauses)).

%% The file must contain a norm_clause for main/0.
test(main_clause_present) :-
    input_file(File),
    reader:read_and_normalise(File, NormClauses),
    member(norm_clause(main, _, _), NormClauses).

%% The body of main/0 must contain exactly two norm_read_string nodes.
test(two_read_strings_in_main) :-
    input_file(File),
    reader:read_and_normalise(File, NormClauses),
    member(norm_clause(main, Body, _), NormClauses),
    findall(RS, body_read_strings(Body, RS), RSList),
    length(RSList, 2).

%% Output goals in main/0 must be wrapped in norm_output.
test(output_goals_tagged) :-
    input_file(File),
    reader:read_and_normalise(File, NormClauses),
    member(norm_clause(main, Body, _), NormClauses),
    findall(OG, body_output_goals(Body, OG), OGList),
    OGList \= [].

%% Variable names are preserved in the main/0 clause.
test(var_names_preserved_in_main) :-
    input_file(File),
    reader:read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, _, VN), NormClauses)),
    % 'Name' and 'Age' should appear in the var-names association list
    memberchk('Name' = _, VN),
    memberchk('Age'  = _, VN).

%% The conjunction structure inside main/0 is a norm_conj tree
%% (not a flat list), reflecting the sequential goals.
test(body_is_norm_conj_tree) :-
    input_file(File),
    reader:read_and_normalise(File, NormClauses),
    member(norm_clause(main, Body, _), NormClauses),
    Body = norm_conj(_, _).

:- end_tests(read_and_normalise).

% ==========================================================================
% Helpers used by the integration tests
% ==========================================================================

%% input_file(-File:atom)
%  Resolve the path to examples/input_example.pl relative to tests/.
input_file(File) :-
    reader_test_dir(Dir),
    file_directory_name(Dir, RepoRoot),
    atomic_list_concat([RepoRoot, '/examples/input_example.pl'], File).

%% body_read_strings(+NormBody, -Node)
%  Backtrack over all norm_read_string nodes in NormBody.
body_read_strings(norm_read_string(S, Se, Pa, L, V),
                  norm_read_string(S, Se, Pa, L, V)).
body_read_strings(norm_conj(A, _), RS) :- body_read_strings(A, RS).
body_read_strings(norm_conj(_, B), RS) :- body_read_strings(B, RS).
body_read_strings(norm_disj(A, _), RS) :- body_read_strings(A, RS).
body_read_strings(norm_disj(_, B), RS) :- body_read_strings(B, RS).
body_read_strings(norm_if_then(C, _),    RS) :- body_read_strings(C, RS).
body_read_strings(norm_if_then(_, T),    RS) :- body_read_strings(T, RS).
body_read_strings(norm_if_then_else(C, _, _), RS) :- body_read_strings(C, RS).
body_read_strings(norm_if_then_else(_, T, _), RS) :- body_read_strings(T, RS).
body_read_strings(norm_if_then_else(_, _, E), RS) :- body_read_strings(E, RS).

%% body_output_goals(+NormBody, -Goal)
%  Backtrack over all norm_output goals in NormBody.
body_output_goals(norm_output(G), G).
body_output_goals(norm_conj(A, _), G) :- body_output_goals(A, G).
body_output_goals(norm_conj(_, B), G) :- body_output_goals(B, G).
body_output_goals(norm_disj(A, _), G) :- body_output_goals(A, G).
body_output_goals(norm_disj(_, B), G) :- body_output_goals(B, G).
body_output_goals(norm_if_then(C, _),    G) :- body_output_goals(C, G).
body_output_goals(norm_if_then(_, T),    G) :- body_output_goals(T, G).
body_output_goals(norm_if_then_else(C, _, _), G) :- body_output_goals(C, G).
body_output_goals(norm_if_then_else(_, T, _), G) :- body_output_goals(T, G).
body_output_goals(norm_if_then_else(_, _, E), G) :- body_output_goals(E, G).
