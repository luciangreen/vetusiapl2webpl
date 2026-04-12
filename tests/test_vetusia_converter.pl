%% tests/test_vetusia_converter.pl
%%
%% Unit tests for the Stage 12 CLI entrypoint (src/vetusia_converter.pl).
%% Tests cover argument parsing logic, validation, and error cases.
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_vetusia_converter.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_vetusia_converter].
%%   ?- run_tests.

:- use_module('../src/vetusia_converter').
:- use_module(library(plunit)).
:- use_module(library(lists)).

% ==========================================================================
% Tests: argument parsing
% ==========================================================================

:- begin_tests(cli_arg_parsing).

test(minimal_args, []) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl'],
        'input.pl', 'output.pl', 8080, '.', hidden).

test(custom_port, []) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--port', '9090'],
        'input.pl', 'output.pl', 9090, '.', hidden).

test(custom_root, []) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--root', 'myapp'],
        'input.pl', 'output.pl', 8080, 'myapp', hidden).

test(custom_state_mode_url, []) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--state-mode', 'url'],
        'input.pl', 'output.pl', 8080, '.', url).

test(custom_state_mode_session, []) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--state-mode', 'session'],
        'input.pl', 'output.pl', 8080, '.', session).

test(all_options, []) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--port', '3000',
         '--root', 'app', '--state-mode', 'hidden'],
        'input.pl', 'output.pl', 3000, 'app', hidden).

test(output_before_input, []) :-
    vetusia_converter:parse_args(
        ['-o', 'output.pl', 'input.pl'],
        'input.pl', 'output.pl', 8080, '.', hidden).

:- end_tests(cli_arg_parsing).

% ==========================================================================
% Tests: argument validation
% ==========================================================================

:- begin_tests(cli_validation).

test(invalid_port_string, [throws(cli_error(_))]) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--port', 'notanumber'],
        _, _, _, _, _).

test(invalid_port_zero, [throws(cli_error(_))]) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--port', '0'],
        _, _, _, _, _).

test(invalid_port_too_large, [throws(cli_error(_))]) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--port', '99999'],
        _, _, _, _, _).

test(invalid_state_mode, [throws(cli_error(_))]) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--state-mode', 'bogus'],
        _, _, _, _, _).

test(missing_input, [throws(cli_error(_))]) :-
    vetusia_converter:parse_args(
        ['-o', 'output.pl'],
        _, _, _, _, _).

test(missing_output, [throws(cli_error(_))]) :-
    vetusia_converter:parse_args(
        ['input.pl'],
        _, _, _, _, _).

test(unknown_option, [throws(cli_error(_))]) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'output.pl', '--unknown', 'val'],
        _, _, _, _, _).

:- end_tests(cli_validation).

% ==========================================================================
% Tests: defaults
% ==========================================================================

:- begin_tests(cli_defaults).

test(default_port) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'out.pl'],
        _, _, Port, _, _),
    Port =:= 8080.

test(default_root) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'out.pl'],
        _, _, _, Root, _),
    Root = '.'.

test(default_state_mode) :-
    vetusia_converter:parse_args(
        ['input.pl', '-o', 'out.pl'],
        _, _, _, _, SM),
    SM = hidden.

:- end_tests(cli_defaults).
