%% tests/test_state_serialiser.pl
%%
%% Unit and integration tests for the Stage 8 state serialisation module
%% (src/state_serialiser.pl).
%%
%% Tests cover:
%%   - state_serialise/2       — term-to-atom conversion
%%   - state_deserialise/2     — atom-to-term parsing with fallback
%%   - Round-trip fidelity     — serialise then deserialise gives back == original
%%   - emit_state_serialiser_helpers/1 — emitted source definitions
%%   - Integration             — generated handler code includes serialise/deserialise
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_state_serialiser.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_state_serialiser].
%%   ?- run_tests.

:- use_module('../src/state_serialiser').
:- use_module(library(plunit)).

% ==========================================================================
% Tests: state_serialise/2
% ==========================================================================

:- begin_tests(state_serialise).

test(atom_serialises_to_atom) :-
    state_serialise(hello, A),
    atom(A).

test(atom_serialises_correctly) :-
    state_serialise(hello, A),
    A == hello.

test(integer_serialises_to_atom) :-
    state_serialise(42, A),
    atom(A).

test(integer_serialises_correctly) :-
    state_serialise(42, A),
    A == '42'.

test(negative_integer_serialises) :-
    state_serialise(-7, A),
    atom(A).

test(float_serialises_to_atom) :-
    state_serialise(3.14, A),
    atom(A).

test(list_serialises_to_atom) :-
    state_serialise([1, 2, 3], A),
    atom(A).

test(empty_list_serialises) :-
    state_serialise([], A),
    atom(A).

test(nested_list_serialises) :-
    state_serialise([[a, b], [c, d]], A),
    atom(A).

test(compound_serialises_to_atom) :-
    state_serialise(foo(bar, baz), A),
    atom(A).

test(compound_with_list_arg_serialises) :-
    state_serialise(f([1, 2], g(x)), A),
    atom(A).

test(atom_with_space_serialises_to_atom) :-
    state_serialise('Hello World', A),
    atom(A).

:- end_tests(state_serialise).

% ==========================================================================
% Tests: state_deserialise/2 — known Prolog terms
% ==========================================================================

:- begin_tests(state_deserialise_prolog_terms).

test(atom_deserialises) :-
    state_deserialise(hello, T),
    T == hello.

test(integer_atom_deserialises_to_integer) :-
    state_deserialise('42', T),
    T == 42.

test(negative_integer_deserialises) :-
    state_deserialise('-7', T),
    T == -7.

test(float_atom_deserialises_to_float) :-
    state_deserialise('3.14', T),
    T == 3.14.

test(list_atom_deserialises_to_list) :-
    state_deserialise('[1,2,3]', T),
    T == [1, 2, 3].

test(empty_list_atom_deserialises) :-
    state_deserialise('[]', T),
    T == [].

test(compound_atom_deserialises) :-
    state_deserialise('foo(bar,baz)', T),
    T == foo(bar, baz).

test(nested_compound_deserialises) :-
    state_deserialise('f([1,2],g(x))', T),
    T == f([1, 2], g(x)).

:- end_tests(state_deserialise_prolog_terms).

% ==========================================================================
% Tests: state_deserialise/2 — fallback for non-Prolog-term atoms
% ==========================================================================

:- begin_tests(state_deserialise_fallback).

%% Atoms that are not valid Prolog terms (e.g. user-typed text with spaces)
%% must be returned as-is via the fallback branch.

test(text_with_space_falls_back) :-
    state_deserialise('Hello World', T),
    T == 'Hello World'.

test(two_words_fall_back) :-
    state_deserialise('foo bar', T),
    T == 'foo bar'.

test(sentence_falls_back) :-
    state_deserialise('Enter your name:', T),
    T == 'Enter your name:'.

test(fallback_always_succeeds) :-
    % Even a completely invalid syntax fragment must not throw.
    state_deserialise('42 foo bar', T),
    T == '42 foo bar'.

:- end_tests(state_deserialise_fallback).

% ==========================================================================
% Tests: round-trip fidelity — serialise then deserialise gives back original
% ==========================================================================

:- begin_tests(round_trip).

test(atom_round_trips) :-
    T0 = hello,
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(integer_round_trips) :-
    T0 = 42,
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(negative_integer_round_trips) :-
    T0 = -99,
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(float_round_trips) :-
    T0 = 2.718,
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(empty_list_round_trips) :-
    T0 = [],
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(integer_list_round_trips) :-
    T0 = [1, 2, 3],
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(atom_list_round_trips) :-
    T0 = [foo, bar, baz],
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(nested_list_round_trips) :-
    T0 = [[1, 2], [3, 4], []],
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(compound_round_trips) :-
    T0 = foo(bar, baz),
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(nested_compound_round_trips) :-
    T0 = f(g(1), h(2, 3)),
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(compound_with_list_round_trips) :-
    T0 = person(john, [age=30, role=admin]),
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(atom_with_spaces_round_trips) :-
    T0 = 'Hello World',
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(zero_round_trips) :-
    T0 = 0,
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

test(deeply_nested_list_round_trips) :-
    T0 = [[[a]], [[b, c]], []],
    state_serialise(T0, A),
    state_deserialise(A, T1),
    T1 == T0.

%% Serialised atoms are themselves atoms (safe for HTML hidden field values).
test(serialised_value_is_atom) :-
    state_serialise([1, 2, 3], A),
    atom(A).

test(serialised_compound_is_atom) :-
    state_serialise(foo(bar), A),
    atom(A).

:- end_tests(round_trip).

% ==========================================================================
% Tests: emit_state_serialiser_helpers/1
% ==========================================================================

:- begin_tests(emit_state_serialiser_helpers).

test(emits_state_serialise_definition) :-
    with_output_to(atom(Out),
                   emit_state_serialiser_helpers(current_output)),
    sub_atom(Out, _, _, _, 'state_serialise').

test(emits_state_deserialise_definition) :-
    with_output_to(atom(Out),
                   emit_state_serialiser_helpers(current_output)),
    sub_atom(Out, _, _, _, 'state_deserialise').

test(emits_term_to_atom_call_in_serialise) :-
    with_output_to(atom(Out),
                   emit_state_serialiser_helpers(current_output)),
    sub_atom(Out, _, _, _, 'term_to_atom').

test(emits_fallback_in_deserialise) :-
    with_output_to(atom(Out),
                   emit_state_serialiser_helpers(current_output)),
    sub_atom(Out, _, _, _, 'catch').

test(emits_non_empty_output) :-
    with_output_to(atom(Out),
                   emit_state_serialiser_helpers(current_output)),
    Out \= ''.

:- end_tests(emit_state_serialiser_helpers).

% ==========================================================================
% Integration tests: generated handler code includes serialise/deserialise
% ==========================================================================

:- use_module('../src/continuation_extractor').
:- use_module('../src/checkpoint_detector').
:- use_module('../src/reader').
:- use_module(library(lists)).

:- prolog_load_context(directory, Dir),
   assert(ss_test_dir(Dir)).

:- begin_tests(state_serialiser_integration).

%% Helper: build a two-read body and generate the handler code as text.
two_step_handler_code(Code) :-
    V1 = _, V2 = _,
    VN = ['Name' = V1, 'Age' = V2],
    Body = norm_conj(
        norm_read_string(user, "\n", "\r", _, V1),
        norm_conj(
            norm_read_string(user, "\n", "\r", _, V2),
            norm_output(format("Hello ~w ~w~n", [V1, V2]))
        )
    ),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, Steps),
    with_output_to(atom(Code),
        maplist(write_cont_step(current_output, VN), Steps)).

%% step_1 receives 'Name' (from step_0's form) and must deserialise it.
test(step_1_contains_state_deserialise) :-
    two_step_handler_code(Code),
    sub_atom(Code, _, _, _, 'state_deserialise').

%% step_1 uses a raw variable ('Name_raw') in http_parameters.
test(step_1_uses_raw_variable_in_params) :-
    two_step_handler_code(Code),
    sub_atom(Code, _, _, _, 'Name_raw').

%% step_1 carries 'Name' as a hidden field — it must serialise it first.
test(step_1_contains_state_serialise) :-
    two_step_handler_code(Code),
    sub_atom(Code, _, _, _, 'state_serialise').

%% step_1 uses a serial variable ('Name_s') as the hidden field value.
test(step_1_uses_serial_variable_in_hidden_field) :-
    two_step_handler_code(Code),
    sub_atom(Code, _, _, _, 'Name_s').

%% step_0 (no received params) should NOT contain state_deserialise.
test(step_0_has_no_deserialise) :-
    V1 = _, V2 = _,
    VN = ['Name' = V1, 'Age' = V2],
    Body = norm_conj(
        norm_read_string(user, "\n", "\r", _, V1),
        norm_conj(
            norm_read_string(user, "\n", "\r", _, V2),
            norm_output(format("Hello ~w ~w~n", [V1, V2]))
        )
    ),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    with_output_to(atom(Code0),
        write_cont_step(current_output, VN, Step0)),
    \+ sub_atom(Code0, _, _, _, 'state_deserialise').

%% Generated code still contains http_parameters (regression check).
test(generated_code_contains_http_parameters) :-
    two_step_handler_code(Code),
    sub_atom(Code, _, _, _, 'http_parameters').

%% Generated code still contains reply_html_page (regression check).
test(generated_code_contains_reply_html_page) :-
    two_step_handler_code(Code),
    sub_atom(Code, _, _, _, 'reply_html_page').

:- end_tests(state_serialiser_integration).

% ==========================================================================
% Integration: emit_html_helpers includes state helpers
% ==========================================================================

:- use_module('../src/html_output').

:- begin_tests(html_helpers_includes_state).

test(emit_html_helpers_includes_state_serialise) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'state_serialise').

test(emit_html_helpers_includes_state_deserialise) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'state_deserialise').

test(emit_html_helpers_still_includes_html_escape) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'html_escape').

:- end_tests(html_helpers_includes_state).
