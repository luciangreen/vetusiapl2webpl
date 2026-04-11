:- module(vetusiapl2webpl, [convert/2]).

/** <module> vetusiapl2webpl — Vetusia Prolog-to-Web-Prolog Converter
 *
 * Converts a terminal Prolog program that uses read_string/5 for user
 * input into a SWI-Prolog HTTP server program that serves HTML pages
 * with form-based interactions — one HTML form step per read_string call.
 *
 * Usage from the SWI-Prolog REPL:
 *   ?- use_module('src/vetusiapl2webpl').
 *   ?- convert('examples/input_example.pl', 'output/web_example.pl').
 *
 * One-command usage from the shell:
 *   swipl -g "use_module('src/vetusiapl2webpl'), \
 *              convert('examples/input_example.pl','output/web_example.pl'), \
 *              halt" -t halt
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

:- use_module(library(lists)).
:- use_module(library(apply)).

% ==========================================================================
% Public API
% ==========================================================================

%% convert(+InputFile:atom, +OutputFile:atom) is det.
%
%  Convert a terminal Prolog source file to a web Prolog server file.
%
%  The converter:
%    1. Reads InputFile and locates the main/0 predicate.
%    2. Splits the body at every read_string/5 call, creating one HTTP
%       handler step per interaction.
%    3. Rewrites output goals (writeln/1, write/1, nl, format/1-2) to
%       HTML elements inside reply_html_page/2.
%    4. Threads captured variables forward as hidden HTML form fields and
%       http_parameters/2 declarations.
%    5. Writes the resulting SWI-Prolog HTTP server program to OutputFile.
%
%  Example:
%    ?- convert('examples/input_example.pl', 'output/web_example.pl').
convert(InputFile, OutputFile) :-
    read_source(InputFile, Clauses),
    find_main(Clauses, MainBody, VarNames, AuxClauses),
    conjunction_to_list(MainBody, Goals),
    split_at_reads(Goals, VarNames, Segments0),
    annotate_accumulated(Segments0, [], Segments),
    open(OutputFile, write, Out),
    write_web_program(Out, Segments, VarNames, AuxClauses),
    close(Out).

% ==========================================================================
% Input: reading Prolog source
% ==========================================================================

%% read_source(+File, -Clauses) is det.
%  Read all terms from File as (Term, VarNames) pairs.
read_source(File, Clauses) :-
    open(File, read, S),
    read_stream(S, Clauses),
    close(S).

read_stream(S, Clauses) :-
    read_term(S, T, [variable_names(VN)]),
    ( T == end_of_file ->
        Clauses = []
    ;   Clauses = [(T, VN) | Rest],
        read_stream(S, Rest)
    ).

%% find_main(+Clauses, -Body, -VN, -Others) is det.
%  Locate the main/0 clause, returning its body, variable-names list,
%  and all remaining (non-main) clauses.
find_main([(T, VN) | Rest], Body, VN, Rest) :-
    T = (main :- Body), !.
find_main([C | Rest], Body, VN, [C | Others]) :-
    find_main(Rest, Body, VN, Others).

% ==========================================================================
% Goal processing
% ==========================================================================

%% conjunction_to_list(+Conj, -Goals) is det.
%  Flatten a Prolog conjunction into a list of atomic goals.
conjunction_to_list((A, B), Goals) :- !,
    conjunction_to_list(A, As),
    conjunction_to_list(B, Bs),
    append(As, Bs, Goals).
conjunction_to_list(true, []) :- !.
conjunction_to_list(G, [G]).

%% split_at_reads(+Goals, +VN, -Segments) is det.
%  Split a goal list into segments at every read_string/5 call.
%  Each segment is seg(Goals, ReadVarName) where ReadVarName is the
%  atom name of the variable captured by read_string, or 'none' for
%  the final segment (which has no trailing read_string).
split_at_reads(Goals, VN, Segs) :-
    split_at_reads_(Goals, VN, [], Segs).

split_at_reads_([], _VN, Acc, [seg(Rev, none)]) :-
    reverse(Acc, Rev).
split_at_reads_([G | Rest], VN, Acc, [seg(Rev, VName) | RestSegs]) :-
    G = read_string(_, _, _, _, V), !,
    var_name_of(V, VN, VName),
    reverse(Acc, Rev),
    split_at_reads_(Rest, VN, [], RestSegs).
split_at_reads_([G | Rest], VN, Acc, Segs) :-
    split_at_reads_(Rest, VN, [G | Acc], Segs).

%% var_name_of(+Var, +VN, -Name) is det.
%  Look up the name of a Prolog variable in a variable-names list.
var_name_of(V, [N = U | _], N) :- V == U, !.
var_name_of(V, [_ | Rest], N) :- var_name_of(V, Rest, N).
var_name_of(_, [], anon).

%% annotate_accumulated(+Segs, +Acc, -AnnotatedSegs) is det.
%  Add the list of variable names accumulated so far to each segment,
%  producing seg(Goals, ReadVarName, AccumulatedVarNames).
annotate_accumulated([], _, []).
annotate_accumulated([seg(Goals, ReadVar) | Rest], Acc,
                     [seg(Goals, ReadVar, Acc) | AnnotRest]) :-
    ( ReadVar \= none ->
        NewAcc = [ReadVar | Acc]
    ;   NewAcc = Acc
    ),
    annotate_accumulated(Rest, NewAcc, AnnotRest).

% ==========================================================================
% Goal classification
% ==========================================================================

%% is_output_goal(+Goal) is semidet.
%  True when Goal is a terminal-output predicate that should be
%  converted to an HTML element rather than kept as a Prolog call.
is_output_goal(writeln(_)).
is_output_goal(write(_)).
is_output_goal(nl).
is_output_goal(format(_, _)).
is_output_goal(format(_)).
is_output_goal(writef(_, _)).
is_output_goal(print(_)).

%% goal_to_html_term(+Goal, -HtmlTerm) is det.
%  Convert a terminal-output goal to an HTML term for reply_html_page/2.
%  Variables inside Goal remain uninstantiated; they will be bound at
%  runtime by http_parameters/2 before reply_html_page/2 is called.
goal_to_html_term(writeln(X), p(X)) :- !.
goal_to_html_term(write(X),   span(X)) :- !.
goal_to_html_term(nl,         br([])) :- !.
goal_to_html_term(print(X),   p(X)) :- !.
goal_to_html_term(format(Fmt, Args), p(runtime_format(Fmt, Args))) :- !.
    % Note: runtime_format/2 is a placeholder term.  In intermediate form
    % steps the format string with variable arguments is simplified to a
    % paragraph showing the format template; for the final step the
    % original format/2 call is kept verbatim in the clause body instead.
goal_to_html_term(format(Fmt), p(Fmt)) :- !.
goal_to_html_term(_, p('')).

% ==========================================================================
% Output: writing the web program
% ==========================================================================

write_web_program(Out, Segs, VN, AuxClauses) :-
    length(Segs, N),
    emit_header_comment(Out),
    emit_use_modules(Out),
    nl(Out),
    emit_handler_decls(Out, N),
    nl(Out),
    emit_init_and_main(Out),
    nl(Out),
    emit_all_handlers(Out, Segs, 0, VN),
    emit_aux_clauses(Out, AuxClauses).

% --------------------------------------------------------------------------
% Boilerplate
% --------------------------------------------------------------------------

emit_header_comment(Out) :-
    format(Out, "%% Generated by vetusiapl2webpl — Vetusia Prolog-to-Web-Prolog Converter~n", []),
    format(Out, "%% --------------------------------------------------~n~n", []).

emit_use_modules(Out) :-
    format(Out, ":- use_module(library(http/thread_httpd)).~n",  []),
    format(Out, ":- use_module(library(http/http_dispatch)).~n", []),
    format(Out, ":- use_module(library(http/html_write)).~n",    []),
    format(Out, ":- use_module(library(http/http_parameters)).~n",[]).

emit_handler_decls(Out, N) :-
    format(Out, ":- http_handler(root(.), step_0, []).~n", []),
    ( N > 1 ->
        N1 is N - 1,
        forall(between(1, N1, I),
               format(Out,
                   ":- http_handler(root(step_~w), step_~w, [method(post)]).~n",
                   [I, I]))
    ; true ).

emit_init_and_main(Out) :-
    format(Out, ":- initialization(main, main).~n~n", []),
    format(Out, "main :-~n    http_server(http_dispatch, [port(8080)]).~n", []).

% --------------------------------------------------------------------------
% Step handlers
% --------------------------------------------------------------------------

emit_all_handlers(_, [], _, _) :- !.
emit_all_handlers(Out, [Seg | Rest], StepNum, VN) :-
    nl(Out),
    emit_handler(Out, Seg, StepNum, VN),
    Next is StepNum + 1,
    emit_all_handlers(Out, Rest, Next, VN).

%% emit_handler(+Out, +Seg, +StepNum, +VN)
%  Write a single HTTP handler clause for one step.
emit_handler(Out, seg(Goals, ReadVar, AccVars), StepNum, VN) :-
    partition(is_output_goal, Goals, OutGoals, CompGoals),
    % Create a fresh Prolog variable for the Request parameter.
    % Step 0 serves a GET request and doesn't inspect the request object,
    % so we use _Request (underscore-prefixed) to signal the variable is
    % intentionally unused and suppress any singleton-variable warnings.
    % Steps 1+ receive POST data and DO inspect Request via http_parameters/2.
    ( StepNum =:= 0 -> ReqName = '_Request' ; ReqName = 'Request' ),
    ExtVN = [ReqName = ReqVar | VN],
    % Handler head
    atom_concat('step_', StepNum, HeadFunctor),
    format(Out, "~w(", [HeadFunctor]),
    write_term(Out, ReqVar, [variable_names(ExtVN), quoted(true)]),
    format(Out, ") :-~n", []),
    % http_parameters/2 (only needed for steps that receive POST data)
    ( StepNum > 0, AccVars \= [] ->
        emit_params(Out, AccVars, ReqVar, VN, ExtVN)
    ; true ),
    % Computation (non-output) goals from the original program
    maplist(emit_compute_goal(Out, ExtVN), CompGoals),
    % HTML reply
    ( ReadVar \= none ->
        emit_form_reply(Out, OutGoals, AccVars, ReadVar,
                        StepNum, StepNum + 1, VN, ExtVN)
    ;   emit_result_reply(Out, OutGoals, CompGoals, AccVars, VN, ExtVN)
    ).

% --------------------------------------------------------------------------
% http_parameters/2 emission
% --------------------------------------------------------------------------

emit_params(Out, AccVars, ReqVar, VN, ExtVN) :-
    maplist(build_param_term(VN), AccVars, ParamTerms),
    format(Out, "    http_parameters(", []),
    write_term(Out, ReqVar, [variable_names(ExtVN), quoted(true)]),
    format(Out, ",~n        [~n", []),
    emit_param_term_list(Out, ParamTerms, ExtVN),
    format(Out, "        ]),~n", []).

%% build_param_term(+VN, +VarName, -ParamTerm)
%  Build a 'VarName'(Var, [atom]) term for http_parameters/2.
build_param_term(VN, VarName, ParamTerm) :-
    find_var_by_name(VarName, VN, Var),
    ParamTerm =.. [VarName, Var, [atom]].

emit_param_term_list(_, [], _).
emit_param_term_list(Out, [P], ExtVN) :- !,
    format(Out, "            ", []),
    write_term(Out, P, [variable_names(ExtVN), quoted(true)]),
    nl(Out).
emit_param_term_list(Out, [P | Rest], ExtVN) :-
    format(Out, "            ", []),
    write_term(Out, P, [variable_names(ExtVN), quoted(true)]),
    format(Out, ",~n", []),
    emit_param_term_list(Out, Rest, ExtVN).

% --------------------------------------------------------------------------
% Inline computation goals
% --------------------------------------------------------------------------

emit_compute_goal(Out, VN, Goal) :-
    format(Out, "    ", []),
    write_term(Out, Goal, [variable_names(VN), quoted(true)]),
    format(Out, ",~n", []).

% --------------------------------------------------------------------------
% Form-based reply (non-final steps)
% --------------------------------------------------------------------------

emit_form_reply(Out, OutGoals, AccVars, ReadVar, StepNum, _NextStep,
                VN, ExtVN) :-
    NextStep is StepNum + 1,
    atom_concat('/step_', NextStep, Action),
    % Hidden fields carry accumulated variables forward
    maplist(build_hidden_input(VN), AccVars, HiddenInputs),
    % Output goals become HTML content
    maplist(goal_to_html_term, OutGoals, OutHtml),
    % Text input for the variable this read_string captures
    TextInput   = input([type=text, name=ReadVar]),
    SubmitInput = input([type=submit, value='Next']),
    % Assemble form children: hidden + output + text + submit
    append(HiddenInputs, OutHtml, Acc1),
    append(Acc1, [TextInput, SubmitInput], FormChildren),
    FormTerm   = form([method=post, action=Action], FormChildren),
    format(atom(TitleAtom), 'Step ~w', [StepNum]),
    ReplyTerm  = reply_html_page(title(TitleAtom), [FormTerm]),
    format(Out, "    ", []),
    write_term(Out, ReplyTerm, [variable_names(ExtVN), quoted(true)]),
    format(Out, ".~n", []).

build_hidden_input(VN, VarName,
                   input([type=hidden, name=VarName, value=V])) :-
    find_var_by_name(VarName, VN, V).

% --------------------------------------------------------------------------
% Result reply (final step)
% --------------------------------------------------------------------------

%  For the last step we use raw format/2 output so that format/2 goals
%  from the original program work naturally with their live variable
%  bindings, without needing intermediate temporary variables.
emit_result_reply(Out, OutGoals, _CompGoals, AccVars, VN, ExtVN) :-
    format(Out, "    format('Content-type: text/html~~n~~n'),~n", []),
    format(Out, "    format('<html><body>~~n'),~n", []),
    % Display all accumulated variable values
    maplist(emit_var_output_line(Out, VN, ExtVN), AccVars),
    % Output goals (converted to HTML-safe writes)
    maplist(emit_result_goal_line(Out, ExtVN), OutGoals),
    format(Out, "    format('</body></html>~~n').~n", []).

emit_var_output_line(Out, VN, ExtVN, VarName) :-
    find_var_by_name(VarName, VN, Var),
    FmtGoal = format('<p>~w</p>~n', [Var]),
    format(Out, "    ", []),
    write_term(Out, FmtGoal, [variable_names(ExtVN), quoted(true)]),
    format(Out, ",~n", []).

emit_result_goal_line(Out, ExtVN, writeln(X)) :- !,
    FmtGoal = format('<p>~w</p>~n', [X]),
    format(Out, "    ", []),
    write_term(Out, FmtGoal, [variable_names(ExtVN), quoted(true)]),
    format(Out, ",~n", []).
emit_result_goal_line(Out, ExtVN, write(X)) :- !,
    FmtGoal = format('<span>~w</span>', [X]),
    format(Out, "    ", []),
    write_term(Out, FmtGoal, [variable_names(ExtVN), quoted(true)]),
    format(Out, ",~n", []).
emit_result_goal_line(Out, _ExtVN, nl) :- !,
    format(Out, "    format('<br/>~~n'),~n", []).
emit_result_goal_line(Out, ExtVN, format(Fmt, Args)) :- !,
    % Keep format/2 as-is — it outputs directly into the HTTP stream
    Goal = format(Fmt, Args),
    format(Out, "    ", []),
    write_term(Out, Goal, [variable_names(ExtVN), quoted(true)]),
    format(Out, ",~n", []).
emit_result_goal_line(Out, ExtVN, format(Fmt)) :- !,
    Goal = format(Fmt),
    format(Out, "    ", []),
    write_term(Out, Goal, [variable_names(ExtVN), quoted(true)]),
    format(Out, ",~n", []).
emit_result_goal_line(Out, ExtVN, Goal) :-
    FmtGoal = format('<p>~w</p>~n', [Goal]),
    format(Out, "    ", []),
    write_term(Out, FmtGoal, [variable_names(ExtVN), quoted(true)]),
    format(Out, ",~n", []).

% --------------------------------------------------------------------------
% Auxiliary helpers
% --------------------------------------------------------------------------

%% find_var_by_name(+Name, +VN, -Var)
%  Find the Prolog variable associated with Name in a VarNames list.
find_var_by_name(Name, [Name = V | _], V) :- !.
find_var_by_name(Name, [_ | Rest], V) :-
    find_var_by_name(Name, Rest, V).

%% emit_aux_clauses(+Out, +Clauses)
%  Write auxiliary clauses from the input (excluding directives and main/0).
emit_aux_clauses(_, []).
emit_aux_clauses(Out, [(Term, _VN) | Rest]) :-
    ( Term = (:- _) ->
        true                        % skip directives from input
    ;   nl(Out),
        portray_clause(Out, Term)
    ),
    emit_aux_clauses(Out, Rest).
