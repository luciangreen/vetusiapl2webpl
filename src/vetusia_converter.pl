/** <module> vetusia_converter — Stage 12: Command Line Interface
 *
 * CLI entry point for the Vetusia Prolog-to-Web-Prolog Converter.
 *
 * Invoke from the shell:
 *
 *   swipl -q -g main -s src/vetusia_converter.pl -- input.pl -o output_web.pl
 *   swipl -q -g main -s src/vetusia_converter.pl -- input.pl -o output_web.pl --port 9090
 *   swipl -q -g main -s src/vetusia_converter.pl -- input.pl -o output_web.pl \
 *         --port 9090 --root myapp --state-mode hidden
 *
 * Options
 * -------
 *   input.pl          (positional, required) — input terminal Prolog file
 *   -o FILE           (required)             — output web Prolog file
 *   --port PORT       (default: 8080)        — default port for the generated server
 *   --root PREFIX     (default: .)           — root path prefix for HTTP handlers
 *   --state-mode MODE (default: hidden)      — state passing mode:
 *                                              hidden  — via HTML hidden form fields
 *                                              url     — via URL query parameters (future)
 *                                              session — via server-side session (future)
 *
 * Exit codes
 * ----------
 *   0 — success
 *   1 — bad arguments, missing file, or conversion error
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

:- module(vetusia_converter, [
    main/0,
    parse_args/6,
    print_usage/0
]).

:- use_module(library(lists)).
:- use_module(library(filesex)).

% Locate web_server_generator relative to this file so the CLI works
% regardless of the working directory from which swipl is invoked.
:- prolog_load_context(directory, Dir),
   atom_concat(Dir, '/web_server_generator', GenMod),
   use_module(GenMod, [generate_web_server/2, generate_web_server/3]).

% ==========================================================================
% Entry point
% ==========================================================================

%% main is det.
%
%  CLI entry point.  Reads flags from current_prolog_flag(argv, _) and
%  runs the conversion pipeline.  Calls halt(0) on success, halt(1) on
%  any error (bad arguments, missing file, conversion failure).
main :-
    current_prolog_flag(argv, RawArgs),
    catch(
        ( parse_args(RawArgs, InputFile, OutputFile, Port, RootPrefix, StateMode),
          run_conversion(InputFile, OutputFile, Port, RootPrefix, StateMode)
        ),
        cli_error(Msg),
        ( format(user_error, "Error: ~w~n~n", [Msg]),
          print_usage,
          halt(1)
        )
    ).

% ==========================================================================
% Argument parsing
% ==========================================================================

%% parse_args(+Args, -Input, -Output, -Port, -Root, -StateMode) is semidet.
%
%  Parse the command-line argument list.
%  Fails (causing usage to be printed) when required arguments are absent
%  or a value is malformed.
parse_args(Args, InputFile, OutputFile, Port, RootPrefix, StateMode) :-
    opts_defaults(DefaultPort, DefaultRoot, DefaultStateMode),
    parse_args_(Args, none, none, DefaultPort, DefaultRoot, DefaultStateMode,
                InputFile0, OutputFile, Port, RootPrefix, StateMode),
    ( InputFile0 = none ->
        cli_error("no input file specified")
    ;   InputFile = InputFile0
    ),
    ( OutputFile = none ->
        cli_error("no output file specified (-o FILE)")
    ;   true
    ),
    validate_state_mode(StateMode),
    validate_port(Port).

opts_defaults(8080, '.', hidden).

parse_args_([], In, Out, Port, Root, SM, In, Out, Port, Root, SM).

parse_args_(['-o', File | Rest], In, _, Port, Root, SM,
            In2, Out, Port2, Root2, SM2) :- !,
    parse_args_(Rest, In, File, Port, Root, SM, In2, Out, Port2, Root2, SM2).

parse_args_(['--port', PortAtom | Rest], In, Out, _, Root, SM,
            In2, Out2, Port, Root2, SM2) :- !,
    ( atom_number(PortAtom, Port), integer(Port), Port > 0, Port < 65536 ->
        true
    ;   cli_error_fmt("invalid port number: ~w", [PortAtom])
    ),
    parse_args_(Rest, In, Out, Port, Root, SM, In2, Out2, Port, Root2, SM2).

parse_args_(['--root', Prefix | Rest], In, Out, Port, _, SM,
            In2, Out2, Port2, Root, SM2) :- !,
    parse_args_(Rest, In, Out, Port, Prefix, SM, In2, Out2, Port2, Root, SM2).

parse_args_(['--state-mode', Mode | Rest], In, Out, Port, Root, _,
            In2, Out2, Port2, Root2, SM) :- !,
    parse_args_(Rest, In, Out, Port, Root, Mode, In2, Out2, Port2, Root2, SM).

parse_args_(['--help' | _], _, _, _, _, _, _, _, _, _, _) :- !,
    print_usage,
    halt(0).

parse_args_([Arg | _], _, _, _, _, _, _, _, _, _, _) :-
    atom_concat('-', _, Arg), !,
    cli_error_fmt("unknown option: ~w", [Arg]).

parse_args_([InputFile | Rest], none, Out, Port, Root, SM,
            In2, Out2, Port2, Root2, SM2) :- !,
    parse_args_(Rest, InputFile, Out, Port, Root, SM,
                In2, Out2, Port2, Root2, SM2).

parse_args_([Extra | _], _, _, _, _, _, _, _, _, _, _) :-
    cli_error_fmt("unexpected argument: ~w", [Extra]).

% ==========================================================================
% Validation
% ==========================================================================

validate_port(Port) :-
    ( integer(Port), Port > 0, Port < 65536 ->
        true
    ;   cli_error_fmt("port must be an integer between 1 and 65535, got: ~w", [Port])
    ).

validate_state_mode(Mode) :-
    ( memberchk(Mode, [hidden, url, session]) ->
        true
    ;   cli_error_fmt("unknown state mode '~w'; valid modes: hidden, url, session", [Mode])
    ).

% ==========================================================================
% Conversion
% ==========================================================================

%% run_conversion(+Input, +Output, +Port, +Root, +StateMode) is det.
%
%  Validates files, optionally warns about unsupported options,
%  then invokes the generation pipeline.
run_conversion(InputFile, OutputFile, Port, RootPrefix, StateMode) :-
    check_input_file(InputFile),
    warn_if_unimplemented(RootPrefix, StateMode),
    ensure_output_dir(OutputFile),
    ( generate_web_server(InputFile, OutputFile, Port) ->
        format("Converted '~w' -> '~w' (port ~w)~n",
               [InputFile, OutputFile, Port])
    ;
        cli_error_fmt("conversion failed for '~w'", [InputFile])
    ).

check_input_file(File) :-
    ( exists_file(File) ->
        true
    ;   cli_error_fmt("input file not found: ~w", [File])
    ).

ensure_output_dir(OutputFile) :-
    file_directory_name(OutputFile, Dir),
    ( Dir = '.' -> true
    ;   make_directory_path(Dir)
    ).

warn_if_unimplemented(RootPrefix, StateMode) :-
    ( RootPrefix \= '.' ->
        format(user_error,
               "warning: --root is accepted but not yet applied by the generator (default '.' used)~n",
               [])
    ;   true
    ),
    ( StateMode \= hidden ->
        format(user_error,
               "warning: --state-mode '~w' is accepted but not yet implemented (hidden field mode used)~n",
               [StateMode])
    ;   true
    ).

% ==========================================================================
% Error helpers
% ==========================================================================

%% cli_error(+Msg) is det.
%  Throw a cli_error/1 exception that main/0 will catch to exit nonzero.
%  Predicates in this module throw rather than calling halt/1 directly,
%  so that callers (including unit tests) can catch the exception.
cli_error(Msg) :-
    throw(cli_error(Msg)).

%% cli_error_fmt(+Fmt, +Args) is det.
%  Like cli_error/1 but with format/2 substitution.
cli_error_fmt(Fmt, Args) :-
    format(atom(Msg), Fmt, Args),
    cli_error(Msg).

% ==========================================================================
% Usage text
% ==========================================================================

%% print_usage is det.
%  Print the usage/help text to standard output.
print_usage :-
    format("Usage:~n"),
    format("  swipl -q -g main -s src/vetusia_converter.pl -- <input.pl> -o <output.pl> [options]~n~n"),
    format("Arguments:~n"),
    format("  <input.pl>             Terminal Prolog source file to convert (required)~n"),
    format("  -o <output.pl>         Output web Prolog server file (required)~n~n"),
    format("Options:~n"),
    format("  --port PORT            Default port for the generated server (default: 8080)~n"),
    format("  --root PREFIX          Root path prefix for HTTP handlers   (default: .)~n"),
    format("  --state-mode MODE      State passing mode: hidden | url | session~n"),
    format("                         (default: hidden)~n"),
    format("  --help                 Show this help message and exit~n~n"),
    format("Examples:~n"),
    format("  swipl -q -g main -s src/vetusia_converter.pl -- input.pl -o output.pl~n"),
    format("  swipl -q -g main -s src/vetusia_converter.pl -- input.pl -o output.pl --port 9090~n"),
    format("  swipl -q -g main -s src/vetusia_converter.pl -- input.pl -o output.pl \\~n"),
    format("        --port 9090 --root myapp --state-mode hidden~n~n"),
    format("Exit codes:~n"),
    format("  0  Conversion completed successfully~n"),
    format("  1  Argument error, missing file, or conversion failure~n").
