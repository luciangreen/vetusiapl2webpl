:- module(continuation_extractor, [
    extract_continuations/4,
    write_cont_steps/3,
    write_cont_step/3,
    cont_step_name/2,
    cont_step_name/3,
    collect_unsupported_messages/2,
    norm_goal_to_raw/2
]).

/** <module> continuation_extractor — Stage 4: Continuation Extraction Engine
 *
 * Takes the list of checkpoints produced by the Stage 3 checkpoint_detector
 * and generates a list of web handler specifications (cont_step/4 terms).
 * Each cont_step describes one HTTP handler step in the generated web program.
 *
 * The engine handles:
 *   - Sequential multi-step flows (multiple reads in a straight-line body)
 *   - Branching flows (if-then-else / disjunction at the continuation level)
 *   - Retry loops (recursive call to the original predicate)
 *
 * cont_step/4 term structure
 * --------------------------
 *   cont_step(StepName, RecvVarNames, PreGoals, Response)
 *
 *   StepName     — atom: handler predicate name (e.g. landing_pad_main, resume_main_1)
 *   RecvVarNames — list of atom names: variables received via http_parameters/2
 *   PreGoals     — list of norm_goal/1 terms to execute before rendering
 *   Response     — response term (see below)
 *
 * Response terms
 * --------------
 *   form_resp(Prompts, InputVarName, HiddenVarNames, NextStep, InputKind)
 *       Render an HTML form with a text/password/textarea input.
 *       Prompts        — list of norm_output/1 goals shown on the form page
 *       InputVarName   — atom: the text-input field name (variable being read)
 *       HiddenVarNames — list of atom names to carry forward as hidden fields
 *       NextStep       — atom: the next handler name
 *       InputKind      — text | password | textarea
 *
 *   menu_resp(Prompts, VarName, Choices, HiddenVarNames, NextStep, InputKind)
 *       Render an HTML form for a numbered menu selection.
 *       Prompts        — list of norm_output/1 goals shown above the menu
 *       VarName        — atom: the form field name for the choice
 *       Choices        — list of menu_choice(Value, Label) terms
 *       HiddenVarNames — list of atom names to carry forward as hidden fields
 *       NextStep       — atom: the next handler name
 *       InputKind      — radio | select | buttons
 *
 *   result_resp(Goals, LiveVars)
 *       Render a final result page.
 *       Goals    — list of norm_* goals (output and/or compute)
 *       LiveVars — list of atom names for all accumulated variables
 *
 *   cond_resp(CondGoals, ThenResp, ElseResp)
 *       Conditional dispatch (inline if-then-else in the handler body).
 *       CondGoals — list of norm_goal/1 terms forming the condition
 *       ThenResp  — nested response term for the Then arm
 *       ElseResp  — nested response term for the Else arm
 *
 *   retry_resp(TargetStep)
 *       Redirect back to TargetStep (used for retry loops).
 *       TargetStep — atom: entry handler to redirect to (e.g. landing_pad_main)
 *
 * Usage
 * -----
 *   ?- use_module('src/reader').
 *   ?- use_module('src/checkpoint_detector').
 *   ?- use_module('src/continuation_extractor').
 *   ?- read_and_normalise('examples/auth_example.pl', Cs),
 *      member(norm_clause(main, Body, VN), Cs),
 *      detect_checkpoints(Body, VN, main/0, CPs),
 *      extract_continuations(CPs, VN, main/0, Steps).
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

:- use_module(library(lists)).
:- use_module(library(apply)).

:- use_module(html_output).
:- use_module(form_generator).
:- use_module(state_serialiser).
:- use_module(menu_recogniser).
:- use_module(control_flow_transformer).

% ==========================================================================
% Public API
% ==========================================================================

%% cont_step_name(+Index:integer, -Name:atom) is det.
%
%  Backward-compatible arity-2 variant.  Delegates to cont_step_name/3 with
%  PredName = none, producing the anonymous names step_0, step_1, …
%  Use cont_step_name/3 when the original predicate name is available.
cont_step_name(N, Name) :- cont_step_name(N, none, Name).

%% cont_step_name(+Index:integer, +PredName:atom, -Name:atom) is det.
%
%  Map a step index and the original predicate name to a meaningful handler
%  atom name (Stage 15 output naming rules):
%
%    Index 0, none     → step_0              (anonymous fallback)
%    Index 0, PredName → landing_pad_<PredName>
%    Index N, none     → step_N              (anonymous fallback)
%    Index N, PredName → resume_<PredName>_<N>
%
%  The landing_pad_* prefix marks the entry GET handler; no HTTP parameters
%  are received and the request argument is intentionally unused (_Request).
%  The resume_* prefix marks POST handlers that resume the program continuation
%  by receiving variables submitted from the previous form step.
cont_step_name(0, none, step_0) :- !.
cont_step_name(0, PredName, Name) :- !,
    atom_concat(landing_pad_, PredName, Name).
cont_step_name(N, none, Name) :- !,
    atom_concat(step_, N, Name).
cont_step_name(N, PredName, Name) :-
    atomic_list_concat([resume_, PredName, '_', N], Name).

%% ce_pred_name(+Head, -PredName) is det.
%
%  Extract the functor name from a F/A head term, or return 'none' when
%  the head is the atom 'none'.  Used to incorporate the original predicate
%  name into generated handler names (Stage 15 naming rules).
ce_pred_name(F/_, F) :- !.
ce_pred_name(none, none).

%% is_landing_pad_name(+Name:atom) is semidet.
%
%  True when Name is a landing-pad handler name — the entry GET handler.
%  Used to select the correct Request variable name in write_cont_step and
%  to determine the redirect target for retry_resp response terms.
is_landing_pad_name(step_0) :- !.
is_landing_pad_name(Name) :- sub_atom(Name, 0, _, _, landing_pad_).

%% extract_continuations(+Checkpoints, +VarNames, +OrigHead, -Steps) is det.
%
%  Convert a list of checkpoint/7 terms (from detect_checkpoints/3-4) into
%  a list of cont_step/4 terms that describe every web handler step.
%
%  Checkpoints — list of checkpoint/7 terms
%  VarNames    — Name=Var association list (from read_term/3 variable_names)
%  OrigHead    — F/A of the original predicate, or 'none'.
%                When F/A is given, norm_goal calls to that predicate in
%                continuation bodies are recognised as retry loops and
%                compiled to retry_resp(landing_pad_<F>).
%  Steps       — result: list of cont_step/4 terms
%
%  Stage 10: Each checkpoint's continuation is analysed for control-flow
%  issues before step generation.  Warnings are printed for unsupported
%  constructs and TODO markers are embedded in the generated code for
%  approximately-preserved constructs (e.g. cut).
extract_continuations([], _VN, _Head, []) :- !.
extract_continuations(Checkpoints, VN, Head, Steps) :-
    Checkpoints = [FirstCP | _],
    FirstCP = checkpoint(_, FirstKind, FirstVarName, FirstPrompts,
                         FirstCont, FirstLiveVars, _),
    % Stage 10: analyse the first continuation for control-flow issues and
    % emit any necessary warnings before code generation begins.
    analyse_norm_body(FirstCont, FirstIssues),
    warn_cf_issues(FirstIssues),
    % step_0: entry GET handler — no parameters received.
    % The hidden vars for the form = LiveVars of FirstCP minus FirstVarName
    % (those are carried forward to step_1; but step_1 = FirstCP's step, and
    %  since it's the first checkpoint, no vars were bound before it, so
    %  HiddenVars0 is typically empty).
    exclude(==(FirstVarName), FirstLiveVars, HiddenVars0),
    ce_pred_name(Head, PredName),
    cont_step_name(1, PredName, FirstNextStep),
    % Stage 9: use menu_resp when the first checkpoint is a menu pattern.
    ( is_menu_checkpoint(FirstCP, VN, FirstChoices, _FirstInvalidAction) ->
        menu_input_kind(FirstChoices, FirstMenuInputKind),
        Step0Resp = menu_resp(FirstPrompts, FirstVarName, FirstChoices,
                              HiddenVars0, FirstNextStep, FirstMenuInputKind)
    ;
        select_input_type(FirstKind, FirstVarName, FirstPrompts, FirstInputType),
        Step0Resp = form_resp(FirstPrompts, FirstVarName, HiddenVars0,
                              FirstNextStep, FirstInputType)
    ),
    cont_step_name(0, PredName, Step0Name),
    Step0 = cont_step(Step0Name, [], [], Step0Resp),
    % Generate steps 1..N from each checkpoint.
    gen_cont_steps(Checkpoints, VN, Head, ContSteps),
    Steps = [Step0 | ContSteps].

%% write_cont_steps(+Out:stream, +Steps:list, +VarNames:list) is det.
%
%  Write the complete generated web program — boilerplate, HTTP handler
%  declarations, server init, html output helpers, and one handler clause
%  per cont_step — to the open output stream Out.
write_cont_steps(Out, Steps, VN) :-
    emit_ce_header_comment(Out),
    nl(Out),
    format(Out, "%% === HTTP Library Imports ===~n", []),
    emit_ce_use_modules(Out),
    nl(Out),
    format(Out, "%% === HTTP Handler Declarations ===~n", []),
    emit_ce_handler_decls(Out, Steps),
    nl(Out),
    format(Out, "%% === Server Bootstrap ===~n", []),
    emit_ce_server_init(Out),
    format(Out, "%% === HTML Output Helpers ===~n", []),
    emit_html_helpers(Out),
    nl(Out),
    format(Out, "%% === HTTP Handler Clauses ===~n", []),
    maplist(write_cont_step(Out, VN), Steps).

% ==========================================================================
% Internal: step generation
% ==========================================================================

%% gen_cont_steps(+CPs, +VN, +Head, -Steps) is det.
%
%  For each checkpoint CPi, generate a cont_step/4 that describes the HTTP
%  handler step_i (the handler that *receives* and processes CPi's input).
gen_cont_steps([], _, _, []).
gen_cont_steps([CP | RestCPs], VN, Head, [Step | RestSteps]) :-
    CP = checkpoint(Id, _Kind, _VarName, _Prompts, Continuation, LiveVars, _Ctx),
    ce_pred_name(Head, PredName),
    cont_step_name(Id, PredName, StepName),
    % Determine how many checkpoints lie within this continuation body.
    % These are the first NCont elements of RestCPs (depth-first order is
    % preserved by Stage 3, so positional slicing works correctly).
    count_reads_in_body(Continuation, NCont),
    ce_take_n(NCont, RestCPs, ContCPs),
    % Split the continuation body: collect leading compute goals as PreGoals
    % and leave the rest for Response compilation.
    collect_pre_goals(Continuation, PreGoals0, RemBody),
    % Compile the remaining body into a Response term.
    compile_cont_body(RemBody, LiveVars, ContCPs, VN, Head, Response0),
    % Move any trailing compute goals that ended up in result_resp into PreGoals.
    ce_extract_result_compute_goals(Response0, PreGoals0, PreGoals, Response),
    % Stage 16: analyse PreGoals for unsupported constructs and warn on terminal.
    maplist(analyse_norm_body, PreGoals, IssueLists),
    flatten(IssueLists, Issues),
    warn_cf_issues(Issues),
    Step = cont_step(StepName, LiveVars, PreGoals, Response),
    gen_cont_steps(RestCPs, VN, Head, RestSteps).

%% collect_pre_goals(+NormBody, -PreGoals, -RemBody) is det.
%
%  Walk NormBody left-to-right collecting leading norm_goal/1 and norm_cut
%  goals into PreGoals (these are compute goals to execute before rendering
%  HTML).  norm_output/1 goals are skipped silently — they are already
%  captured in the next checkpoint's Prompts field and will be emitted there.
%  Stops at the first norm_read_*, norm_if_then_else, norm_disj, or
%  norm_if_then.
%
%  Stage 10: norm_cut is collected as a pre-goal so that a cut in sequential
%  context is preserved in the generated handler's computation prefix.
collect_pre_goals(norm_conj(norm_goal(G), Rest), [norm_goal(G) | More], RemBody) :- !,
    collect_pre_goals(Rest, More, RemBody).
collect_pre_goals(norm_conj(norm_cut, Rest), [norm_cut | More], RemBody) :- !,
    collect_pre_goals(Rest, More, RemBody).
collect_pre_goals(norm_conj(norm_output(_), Rest), Goals, RemBody) :- !,
    collect_pre_goals(Rest, Goals, RemBody).
collect_pre_goals(norm_conj(norm_true, Rest), Goals, RemBody) :- !,
    collect_pre_goals(Rest, Goals, RemBody).
collect_pre_goals(norm_true, [], norm_true) :- !.
collect_pre_goals(Body, [], Body).

%% compile_cont_body(+RemBody, +LiveVars, +ContCPs, +VN, +Head, -Response) is det.
%
%  Compile RemBody (the body remaining after collect_pre_goals) into a
%  Response term.
%
%  RemBody  — normalised body starting at the first interesting goal
%  LiveVars — atom names bound in this step (used for hidden fields)
%  ContCPs  — checkpoints within RemBody (positional slice of RestCPs)
%  VN       — Name=Var association list
%  Head     — F/A or none (for retry detection)
%  Response — form_resp | result_resp | cond_resp | retry_resp | todo_resp

% Empty / true body → result page with nothing to show.
compile_cont_body(norm_true, LiveVars, _ContCPs, _VN, _Head,
                  result_resp([], LiveVars)) :- !.

% norm_cut as the entire remaining body: in the web context there are no
% choice points, so the cut has no observable effect.  Return an empty
% result page wrapped in a todo_resp so that a TODO comment is emitted in
% the generated source, alerting the developer that cut semantics differ.
% Stage 10: approximately preserved — emit TODO marker using the canonical
% message from control_flow_transformer:cf_issue_message/2.
compile_cont_body(norm_cut, LiveVars, _ContCPs, _VN, _Head,
                  todo_resp(Msg, result_resp([], LiveVars))) :- !,
    cf_issue_message(issue(cut_sequential, sequential, norm_cut), Msg).

% If-then-else at the top level of the continuation.
compile_cont_body(norm_if_then_else(Cond, Then, Else), LiveVars, ContCPs, VN, Head,
                  cond_resp(CondGoals, ThenResp, ElseResp)) :- !,
    ce_norm_to_goal_list(Cond, CondGoals),
    count_reads_in_body(Then, NThen),
    ce_take_n(NThen, ContCPs, ThenCPs),
    ce_drop_n(NThen, ContCPs, ElseCPs),
    compile_cont_body(Then, LiveVars, ThenCPs, VN, Head, ThenResp),
    compile_cont_body(Else, LiveVars, ElseCPs, VN, Head, ElseResp).

% If-then (no else) at the top level — else arm is an empty result.
compile_cont_body(norm_if_then(Cond, Then), LiveVars, ContCPs, VN, Head,
                  cond_resp(CondGoals, ThenResp, result_resp([], LiveVars))) :- !,
    ce_norm_to_goal_list(Cond, CondGoals),
    compile_cont_body(Then, LiveVars, ContCPs, VN, Head, ThenResp).

% Disjunction at the top level — treated as unconditional cond_resp.
compile_cont_body(norm_disj(A, B), LiveVars, ContCPs, VN, Head,
                  cond_resp([], AResp, BResp)) :- !,
    count_reads_in_body(A, NA),
    ce_take_n(NA, ContCPs, ACPs),
    ce_drop_n(NA, ContCPs, BCPs),
    compile_cont_body(A, LiveVars, ACPs, VN, Head, AResp),
    compile_cont_body(B, LiveVars, BCPs, VN, Head, BResp).

% A single norm_goal that is a direct recursive call → retry.
compile_cont_body(norm_goal(Call), _LiveVars, _ContCPs, _VN, Head,
                  retry_resp(LandingName)) :-
    Head \= none,
    Head = F/A,
    functor(Call, F, A), !,
    cont_step_name(0, F, LandingName).

% A body with no reads that contains a recursive call somewhere → retry.
% (Handles cases like norm_conj(norm_output(invalid), norm_goal(main)).)
compile_cont_body(NormBody, _LiveVars, _ContCPs, _VN, Head,
                  retry_resp(LandingName)) :-
    Head \= none,
    Head = F/A,
    \+ contains_read_in_body(NormBody),
    ce_body_has_call(NormBody, F, A), !,
    cont_step_name(0, F, LandingName).

% Body contains at least one read — generate form_resp (or menu_resp for
% menu patterns) using the first remaining checkpoint (ContCPs head).
compile_cont_body(NormBody, _LiveVars, [NextCP | _], VN, Head, Response) :-
    contains_read_in_body(NormBody), !,
    NextCP = checkpoint(Id, Kind, InputVarName, Prompts, _, NextLiveVars, _),
    % Hidden vars = what step_{Id} receives minus the var it is about to read.
    exclude(==(InputVarName), NextLiveVars, HiddenVarNames),
    ce_pred_name(Head, PredName),
    cont_step_name(Id, PredName, NextStep),
    % Stage 9: use menu_resp when the next checkpoint is a menu pattern.
    ( is_menu_checkpoint(NextCP, VN, Choices, _InvalidAction) ->
        menu_input_kind(Choices, MenuInputKind),
        Response = menu_resp(Prompts, InputVarName, Choices,
                             HiddenVarNames, NextStep, MenuInputKind)
    ;
        select_input_type(Kind, InputVarName, Prompts, InputKind),
        Response = form_resp(Prompts, InputVarName, HiddenVarNames,
                             NextStep, InputKind)
    ).

% Terminal body with no reads and no retry — result page.
compile_cont_body(NormBody, LiveVars, _ContCPs, _VN, _Head,
                  result_resp(Goals, LiveVars)) :-
    ce_norm_to_goal_list(NormBody, Goals).

%% ce_extract_result_compute_goals(+Response0, +PreGoals0, -PreGoals, -Response) is det.
%
%  If Response0 is a result_resp whose Goals contain compute goals (norm_goal
%  or norm_cut terms), move those compute goals to the end of PreGoals0 so
%  that they are executed as Prolog goals rather than being rendered as HTML.
%  Non-compute goals (norm_output, etc.) remain in the result_resp body.
%  All other response kinds are passed through unchanged.
ce_extract_result_compute_goals(result_resp(Goals, LV), PreGoals0, PreGoals,
                                result_resp(OutGoals, LV)) :- !,
    include(ce_is_compute_norm_goal, Goals, ComputeGoals),
    exclude(ce_is_compute_norm_goal, Goals, OutGoals),
    append(PreGoals0, ComputeGoals, PreGoals).
ce_extract_result_compute_goals(Response, PreGoals, PreGoals, Response).

%% ce_is_compute_norm_goal(+Goal) is semidet.
%
%  True when Goal is a norm_goal/1 or norm_cut — a computation goal that
%  should be executed as Prolog rather than rendered as HTML output.
ce_is_compute_norm_goal(norm_goal(_)).
ce_is_compute_norm_goal(norm_cut).



%% count_reads_in_body(+NormBody, -N) is det.
%
%  Count the total number of norm_read_string / norm_read_password goals
%  inside NormBody (recursively, including all branches).
count_reads_in_body(norm_read_string(_, _, _, _, _), 1) :- !.
count_reads_in_body(norm_read_password(_, _),         1) :- !.
count_reads_in_body(norm_read_password(_),             1) :- !.
count_reads_in_body(norm_conj(A, B), N) :- !,
    count_reads_in_body(A, NA),
    count_reads_in_body(B, NB),
    N is NA + NB.
count_reads_in_body(norm_disj(A, B), N) :- !,
    count_reads_in_body(A, NA),
    count_reads_in_body(B, NB),
    N is NA + NB.
count_reads_in_body(norm_if_then(_, T), N) :- !,
    count_reads_in_body(T, N).
count_reads_in_body(norm_if_then_else(_, T, E), N) :- !,
    count_reads_in_body(T, NT),
    count_reads_in_body(E, NE),
    N is NT + NE.
count_reads_in_body(_, 0).

%% contains_read_in_body(+NormBody) is semidet.
%
%  True when NormBody contains at least one read goal.
contains_read_in_body(NormBody) :-
    count_reads_in_body(NormBody, N), N > 0.

%% ce_body_has_call(+NormBody, +F, +A) is semidet.
%
%  True when NormBody contains at least one norm_goal(Call) where
%  functor(Call, F, A).
ce_body_has_call(norm_goal(Call), F, A) :-
    functor(Call, F, A), !.
ce_body_has_call(norm_conj(X, Y), F, A) :-
    ( ce_body_has_call(X, F, A) -> true ; ce_body_has_call(Y, F, A) ).
ce_body_has_call(norm_disj(X, Y), F, A) :-
    ( ce_body_has_call(X, F, A) -> true ; ce_body_has_call(Y, F, A) ).
ce_body_has_call(norm_if_then(_, T), F, A) :-
    ce_body_has_call(T, F, A).
ce_body_has_call(norm_if_then_else(_, T, E), F, A) :-
    ( ce_body_has_call(T, F, A) -> true ; ce_body_has_call(E, F, A) ).

%% ce_norm_to_goal_list(+NormBody, -GoalList) is det.
%
%  Flatten the left-spine of a norm_conj tree into a flat list.
%  (Local copy of checkpoint_detector's norm_to_goal_list/2.)
ce_norm_to_goal_list(norm_conj(A, B), Goals) :- !,
    ce_norm_to_goal_list(A, GA),
    ce_norm_to_goal_list(B, GB),
    append(GA, GB, Goals).
ce_norm_to_goal_list(norm_true, []) :- !.
ce_norm_to_goal_list(G, [G]).

%% ce_take_n(+N, +List, -Prefix) is det.
%
%  Take the first N elements from List as Prefix.
%  If List has fewer than N elements, return the whole list.
ce_take_n(0, _, []) :- !.
ce_take_n(_, [], []) :- !.
ce_take_n(N, [H | T], [H | Rest]) :-
    N > 0,
    N1 is N - 1,
    ce_take_n(N1, T, Rest).

%% ce_drop_n(+N, +List, -Suffix) is det.
%
%  Drop the first N elements from List; Suffix is the remainder.
ce_drop_n(0, List, List) :- !.
ce_drop_n(_, [], []) :- !.
ce_drop_n(N, [_ | T], Rest) :-
    N > 0,
    N1 is N - 1,
    ce_drop_n(N1, T, Rest).

%% ce_find_var(+Name, +VN, -Var) is det.
%
%  Look up the Prolog variable associated with Name in VN.
%  (Local copy of vetusiapl2webpl's find_var_by_name/3.)
ce_find_var(Name, [Name = V | _], V) :- !.
ce_find_var(Name, [_ | Rest], V) :-
    ce_find_var(Name, Rest, V).

% ==========================================================================
% Internal: code generation — boilerplate
% ==========================================================================

emit_ce_header_comment(Out) :-
    format(Out, "%% Generated by vetusiapl2webpl — continuation_extractor~n", []),
    format(Out, "%% --------------------------------------------------~n~n", []).

emit_ce_use_modules(Out) :-
    format(Out, ":- use_module(library(http/thread_httpd)).~n",  []),
    format(Out, ":- use_module(library(http/http_dispatch)).~n", []),
    format(Out, ":- use_module(library(http/html_write)).~n",    []),
    format(Out, ":- use_module(library(http/http_parameters)).~n",[]),
    format(Out, ":- use_module(library(http/http_header)).~n",   []).

emit_ce_handler_decls(Out, Steps) :-
    ( Steps = [cont_step(LandingPadName, _, _, _) | PostSteps] -> true
    ;   LandingPadName = step_0, PostSteps = []
    ),
    format(Out, ":- http_handler(root(.), ~w, []).~n", [LandingPadName]),
    maplist(emit_ce_handler_decl(Out), PostSteps).

is_post_step(cont_step(Name, _, _, _)) :- \+ is_landing_pad_name(Name).

emit_ce_handler_decl(Out, cont_step(Name, _, _, _)) :-
    format(Out, ":- http_handler(root(~w), ~w, [method(post)]).~n", [Name, Name]).

emit_ce_server_init(Out) :-
    format(Out, ":- initialization(main, main).~n~n", []),
    format(Out, "main :-~n    http_server(http_dispatch, [port(8080)]).~n", []).

% ==========================================================================
% Internal: code generation — handler clause per step
% ==========================================================================

%% write_cont_step(+Out, +VN, +Step) is det.
%
%  Write one HTTP handler clause for the given cont_step/4 term.
%
%  Stage 8 state preservation:
%    For each received variable, http_parameters binds a "raw" counterpart
%    (e.g. Name_raw) and state_deserialise/2 converts it to the original
%    Prolog term (Name).  For each hidden field in the response, a "serial"
%    counterpart (e.g. Name_s) is produced by state_serialise/2 and used as
%    the hidden field value so that complex terms survive the round-trip.
%
%  Stage 10: Before writing the clause, any todo_resp nodes in Response are
%  scanned and their TODO messages are emitted as %% TODO: comments in the
%  generated source so that developers can identify constructs that were not
%  fully preserved.
write_cont_step(Out, VN, cont_step(StepName, RecvVarNames, PreGoals, Response)) :-
    % Request variable: underscore-prefixed for the landing-pad (never used),
    % plain for all POST steps (passed to http_parameters/2 and http_redirect/3).
    ( is_landing_pad_name(StepName) -> ReqAtom = '_Request' ; ReqAtom = 'Request' ),

    % ── Stage 8: create raw variable pairs for http_parameters ────────────
    %  For each received variable 'Name', create a fresh 'Name_raw' variable.
    maplist(raw_var_name, RecvVarNames, RawNames),
    maplist(make_fresh_pair, RawNames, RawPairs),

    % ── Stage 8: create serial variable pairs for hidden field values ─────
    %  Collect all hidden variable names from the response tree, then create
    %  fresh 'Name_s' variables for each.
    collect_response_hidden_vars(Response, HiddenVarNames),
    maplist(serial_var_name, HiddenVarNames, SerialNames),
    maplist(make_fresh_pair, SerialNames, SerialPairs),

    % Extended VN for write_term (includes raw, serial, and original vars).
    append(RawPairs, SerialPairs, AuxPairs),
    append(AuxPairs, VN, AllVN),
    ExtVN = [ReqAtom = ReqVar | AllVN],

    % Build http_parameters goal using raw variables.
    build_params_with_raws(RecvVarNames, ReqVar, RawPairs, ParamsGoal),

    % Build state_deserialise/2 goals: one per received variable.
    build_deserialise_goals(RecvVarNames, VN, RawPairs, DeserGoals),

    % Compute goals from the cont_step PreGoals.
    maplist(norm_goal_to_call, PreGoals, PreCalls),

    % Build response goal (uses serial pairs for hidden field serialisation).
    response_to_goal(Response, ReqVar, VN, SerialPairs, RespGoal),

    % Assemble the full clause body.
    append([ParamsGoal | DeserGoals], PreCalls, PreBody),
    append(PreBody, [RespGoal], AllGoals),
    ce_goals_to_conj(AllGoals, Body),

    Head =.. [StepName, ReqVar],
    Clause = (Head :- Body),
    nl(Out),
    % Stage 15: emit a section comment marking this handler's role.
    emit_step_comment(Out, StepName, RecvVarNames),
    % Stage 10: emit TODO comments for any approximately-preserved constructs.
    collect_todo_messages(Response, TodoMsgs),
    maplist(emit_todo_comment(Out), TodoMsgs),
    % Stage 16: emit UNSUPPORTED comments for not-preserved constructs found
    % in PreGoals (compute goals that passed through from the source program).
    collect_unsupported_messages(PreGoals, UnsupportedMsgs),
    maplist(emit_unsupported_comment(Out), UnsupportedMsgs),
    % write_term preserves variable names from ExtVN.
    write_term(Out, Clause, [variable_names(ExtVN), quoted(true)]),
    format(Out, ".~n", []).

% ── Stage 8: state-preservation helpers ───────────────────────────────────

%% raw_var_name(+VarName:atom, -RawName:atom) is det.
%
%  Compute the "raw" counterpart name for a received variable.
%  e.g.  'Name' → 'Name_raw'
raw_var_name(VarName, RawName) :-
    atom_concat(VarName, '_raw', RawName).

%% serial_var_name(+VarName:atom, -SerName:atom) is det.
%
%  Compute the "serial" counterpart name for a hidden-state variable.
%  e.g.  'Name' → 'Name_s'
serial_var_name(VarName, SerName) :-
    atom_concat(VarName, '_s', SerName).

%% make_fresh_pair(+Name:atom, -Pair) is det.
%
%  Create a fresh Name=Var pair where Var is an uninstantiated Prolog
%  variable.  Each call creates a distinct fresh variable.
make_fresh_pair(Name, Name = _).

%% build_params_with_raws(+VarNames, +ReqVar, +RawPairs, -Goal) is det.
%
%  Build an http_parameters/2 goal that binds each variable to its raw
%  counterpart in RawPairs.  Returns 'true' for an empty variable list.
build_params_with_raws([], _, _, true) :- !.
build_params_with_raws(VarNames, ReqVar, RawPairs,
                       http_parameters(ReqVar, ParamTerms)) :-
    maplist(make_raw_param_term(RawPairs), VarNames, ParamTerms).

%% make_raw_param_term(+RawPairs, +VarName, -ParamTerm) is det.
%
%  Build a 'VarName'(RawVar, [atom]) term for http_parameters/2 where
%  RawVar is the raw variable looked up from RawPairs.
make_raw_param_term(RawPairs, VarName, ParamTerm) :-
    raw_var_name(VarName, RawName),
    ce_find_var(RawName, RawPairs, RawVar),
    ParamTerm =.. [VarName, RawVar, [atom]].

%% build_deserialise_goals(+VarNames, +VN, +RawPairs, -Goals) is det.
%
%  Build a list of state_deserialise/2 goals, one per variable in VarNames.
%  Each goal: state_deserialise(VarName_raw, VarName)
build_deserialise_goals([], _, _, []).
build_deserialise_goals([VarName | Rest], VN, RawPairs,
                        [state_deserialise(RawVar, Var) | RestGoals]) :-
    ce_find_var(VarName, VN, Var),
    raw_var_name(VarName, RawName),
    ce_find_var(RawName, RawPairs, RawVar),
    build_deserialise_goals(Rest, VN, RawPairs, RestGoals).

%% collect_response_hidden_vars(+Response, -HiddenVarNames) is det.
%
%  Collect the union of all HiddenVarNames from every form_resp / menu_resp
%  node in the response tree.
%
%  Stage 10: todo_resp delegates to its fallback response.
collect_response_hidden_vars(form_resp(_, _, HiddenVarNames, _, _),
                             HiddenVarNames) :- !.
collect_response_hidden_vars(menu_resp(_, _, _, HiddenVarNames, _, _),
                             HiddenVarNames) :- !.
collect_response_hidden_vars(cond_resp(_, ThenResp, ElseResp), All) :- !,
    collect_response_hidden_vars(ThenResp, ThenH),
    collect_response_hidden_vars(ElseResp, ElseH),
    append(ThenH, ElseH, All0),
    list_to_set(All0, All).
collect_response_hidden_vars(todo_resp(_, FallbackResp), All) :- !,
    collect_response_hidden_vars(FallbackResp, All).
collect_response_hidden_vars(_, []).

%% make_hidden_to_serial_entry(+SerialPairs, +VarName, -Entry) is det.
%
%  Build a VarName=SerialVar entry that maps the hidden variable name to
%  its serial-variable counterpart.  Used to construct the HiddenVN list
%  passed to generate_form/7 so hidden inputs use the serialised values.
make_hidden_to_serial_entry(SerialPairs, VarName, VarName = SerVar) :-
    serial_var_name(VarName, SerName),
    ce_find_var(SerName, SerialPairs, SerVar).

%% make_serialise_goal(+VN, +SerialPairs, +VarName, -Goal) is det.
%
%  Build a state_serialise/2 goal: state_serialise(Var, Var_s)
%  where Var is the original variable and Var_s is its serial counterpart.
make_serialise_goal(VN, SerialPairs, VarName,
                    state_serialise(Var, SerVar)) :-
    ce_find_var(VarName, VN, Var),
    serial_var_name(VarName, SerName),
    ce_find_var(SerName, SerialPairs, SerVar).

% ── Original build_params_goal kept for reference ─────────────────────────

%% build_params_goal(+VarNames, +ReqVar, +VN, -Goal) is det.
%
%  Build the http_parameters/2 goal for the given variable names.
%  Returns 'true' when the list is empty (step_0 has no parameters).
%  NOTE: superseded by build_params_with_raws/4 in write_cont_step.
build_params_goal([], _, _, true) :- !.
build_params_goal(VarNames, ReqVar, VN, http_parameters(ReqVar, ParamTerms)) :-
    maplist(make_param_term(VN), VarNames, ParamTerms).

%% make_param_term(+VN, +VarName, -ParamTerm) is det.
%
%  Build a 'VarName'(Var, [atom]) term for http_parameters/2.
make_param_term(VN, VarName, ParamTerm) :-
    ce_find_var(VarName, VN, Var),
    ParamTerm =.. [VarName, Var, [atom]].

%% norm_goal_to_call(+NormGoal, -Call) is det.
%
%  Unwrap a norm_goal/1 or norm_cut to its raw Prolog call.
norm_goal_to_call(norm_goal(G), G) :- !.
norm_goal_to_call(norm_cut, !)    :- !.
norm_goal_to_call(G, G).

%% response_to_goal(+Response, +ReqVar, +VN, +SerialPairs, -Goal) is det.
%
%  Convert a Response term into a Prolog goal term suitable for inclusion
%  in a handler clause body.
%
%  SerialPairs — list of 'Name_s' = SerVar pairs created in write_cont_step.
%    For form_resp / menu_resp: serial variables are used as hidden field
%    values, and state_serialise/2 goals are prepended to the form goal.
%    For other response types: SerialPairs is passed through but not used
%    at the top level.
response_to_goal(form_resp(Prompts, InputVarName, HiddenVarNames, NextStep,
                           InputKind),
                 _ReqVar, VN, SerialPairs, Goal) :-
    % Build HiddenVN: maps each hidden var name to its serial variable.
    maplist(make_hidden_to_serial_entry(SerialPairs), HiddenVarNames, HiddenVN),
    % Build state_serialise/2 goals for each hidden variable.
    maplist(make_serialise_goal(VN, SerialPairs), HiddenVarNames, SerialGoals),
    % Generate form using the serial VN so hidden fields carry serialised values.
    generate_form(Prompts, InputVarName, HiddenVarNames, NextStep,
                  InputKind, HiddenVN, Form),
    FormGoal = reply_html_page(title('Form'), [Form]),
    ce_goals_to_conj(SerialGoals, SerialConj),
    ( SerialConj = true ->
        Goal = FormGoal
    ;   Goal = (SerialConj, FormGoal)
    ).

% Stage 9: menu_resp — generate a menu selection form.
response_to_goal(menu_resp(Prompts, VarName, Choices, HiddenVarNames, NextStep,
                           InputKind),
                 _ReqVar, VN, SerialPairs, Goal) :-
    maplist(make_hidden_to_serial_entry(SerialPairs), HiddenVarNames, HiddenVN),
    maplist(make_serialise_goal(VN, SerialPairs), HiddenVarNames, SerialGoals),
    generate_menu_form(Prompts, VarName, Choices, HiddenVarNames, NextStep,
                       InputKind, HiddenVN, Form),
    FormGoal = reply_html_page(title('Form'), [Form]),
    ce_goals_to_conj(SerialGoals, SerialConj),
    ( SerialConj = true ->
        Goal = FormGoal
    ;   Goal = (SerialConj, FormGoal)
    ).

response_to_goal(result_resp(Goals, _LiveVars), _ReqVar, _VN, _SerialPairs,
                 Goal) :-
    maplist(norm_output_to_result_call, Goals, Lines),
    ce_goals_to_conj(
        [ html_page_header('Result')
        | Lines
        ],
        PreGoal),
    LastGoal = html_page_footer,
    ( PreGoal = true ->
        Goal = LastGoal
    ;   Goal = (PreGoal, LastGoal)
    ).

response_to_goal(cond_resp([], ThenResp, ElseResp), ReqVar, VN,
                 SerialPairs, Goal) :- !,
    response_to_goal(ThenResp, ReqVar, VN, SerialPairs, ThenGoal),
    response_to_goal(ElseResp, ReqVar, VN, SerialPairs, ElseGoal),
    Goal = (ThenGoal ; ElseGoal).

response_to_goal(cond_resp(CondGoals, ThenResp, ElseResp), ReqVar, VN,
                 SerialPairs, Goal) :-
    % CondGoals are norm_goal/1 terms; unwrap to raw Prolog goals before
    % building the conjunction that appears in the if-then-else condition.
    maplist(norm_goal_to_raw, CondGoals, RawCondGoals),
    ce_goals_to_conj(RawCondGoals, Cond),
    response_to_goal(ThenResp, ReqVar, VN, SerialPairs, ThenGoal),
    response_to_goal(ElseResp, ReqVar, VN, SerialPairs, ElseGoal),
    ( Cond = true ->
        Goal = (ThenGoal ; ElseGoal)
    ;   Goal = (Cond -> ThenGoal ; ElseGoal)
    ).

response_to_goal(retry_resp(TargetStep), ReqVar, _VN, _SerialPairs, Goal) :-
    ( is_landing_pad_name(TargetStep) ->
        Goal = http_redirect(see_other, root(.), ReqVar)
    ;   atom_concat('/', TargetStep, Path),
        Goal = http_redirect(see_other, root(Path), ReqVar)
    ).

% Stage 10: todo_resp — delegate to the fallback response for goal generation.
% The TODO comment itself is emitted as a Prolog comment by write_cont_step
% (via collect_todo_messages/2 + emit_todo_comment/2) before the clause is
% written, not as a runtime goal in the clause body.
response_to_goal(todo_resp(_Reason, FallbackResp), ReqVar, VN,
                 SerialPairs, Goal) :-
    response_to_goal(FallbackResp, ReqVar, VN, SerialPairs, Goal).

% ==========================================================================
% Internal: Stage 10 — TODO comment helpers
% ==========================================================================

%% collect_todo_messages(+Response, -Messages) is det.
%
%  Recursively collect all TODO message atoms from todo_resp nodes in the
%  response tree.  Messages is a list of atoms (one per todo_resp node).
collect_todo_messages(todo_resp(Reason, FallbackResp), [Reason | Rest]) :- !,
    collect_todo_messages(FallbackResp, Rest).
collect_todo_messages(cond_resp(_, ThenResp, ElseResp), Msgs) :- !,
    collect_todo_messages(ThenResp, ThenMsgs),
    collect_todo_messages(ElseResp, ElseMsgs),
    append(ThenMsgs, ElseMsgs, Msgs).
collect_todo_messages(_, []).

%% emit_todo_comment(+Out, +Message) is det.
%
%  Write a TODO comment line to the output stream Out.
emit_todo_comment(Out, Message) :-
    format(Out, "%% TODO: ~w~n", [Message]).

% ==========================================================================
% Internal: Stage 16 — UNSUPPORTED comment helpers
% ==========================================================================

%% collect_unsupported_messages(+PreGoals, -Messages) is det.
%
%  Walk the PreGoals list (list of norm_goal/1 terms) and collect a
%  human-readable message for every goal whose construct_preservation_class
%  is not_preserved.  Messages is a list of atoms (one per not-preserved goal).
collect_unsupported_messages([], []).
collect_unsupported_messages([G | Rest], Msgs) :-
    ( construct_preservation_class(G, not_preserved(Reason)) ->
        norm_goal_to_raw(G, RawGoal),
        term_to_atom(RawGoal, GoalAtom),
        atomic_list_concat(['Goal ', GoalAtom, ' — ', Reason,
                            ' — passes through unchanged; verify manually.'],
                           Msg),
        collect_unsupported_messages(Rest, RestMsgs),
        Msgs = [Msg | RestMsgs]
    ;   collect_unsupported_messages(Rest, Msgs)
    ).

%% norm_goal_to_raw(+NormGoal, -RawGoal) is det.
%
%  Extract the raw goal term from a norm_goal/1 wrapper.
%  Returns the norm term unchanged for non-norm_goal constructs.
norm_goal_to_raw(norm_goal(G), G) :- !.
norm_goal_to_raw(G, G).

%% emit_unsupported_comment(+Out, +Message) is det.
%
%  Write an UNSUPPORTED comment line to the output stream Out.
emit_unsupported_comment(Out, Message) :-
    format(Out, "%% UNSUPPORTED: ~w~n", [Message]).

%% emit_step_comment(+Out, +StepName, +RecvVarNames) is det.
%
%  Write a section comment before a handler clause marking its role
%  (Stage 15 comment insertion rules).
%  Landing-pad handlers are labelled "Entry GET handler (landing page)".
%  Resume handlers list the variables they receive via http_parameters/2.
emit_step_comment(Out, StepName, RecvVarNames) :-
    ( is_landing_pad_name(StepName) ->
        format(Out, "%% --- ~w : Entry GET handler (landing page) ---~n", [StepName])
    ;   ( RecvVarNames = [] ->
            format(Out, "%% --- ~w : POST handler ---~n", [StepName])
        ;   atomic_list_concat(RecvVarNames, ', ', VarList),
            format(Out, "%% --- ~w : POST handler (receives: ~w) ---~n",
                   [StepName, VarList])
        )
    ).

% ==========================================================================
% Internal: HTML / output helpers
% ==========================================================================

% norm_output_to_html_term/2 and norm_output_to_result_call/2 are imported
% from the html_output module (Stage 6).

%% ce_goals_to_conj(+GoalList, -Conj) is det.
%
%  Convert a list of Prolog goal terms to a right-associative conjunction.
%  'true' goals are filtered out.  Returns 'true' for an empty list.
ce_goals_to_conj(Goals, Conj) :-
    exclude(==(true), Goals, Goals1),
    list_to_conj(Goals1, Conj).

list_to_conj([],       true)               :- !.
list_to_conj([G],      G)                  :- !.
list_to_conj([G | Rs], (G, RestConj))      :-
    list_to_conj(Rs, RestConj).

%% norm_goal_to_raw(+NormGoal, -Raw) is det.
%
%  Strip the norm_goal/1 wrapper to obtain the raw Prolog goal term.
%  Used when building the condition for a Prolog if-then-else expression.
norm_goal_to_raw(norm_goal(G), G) :- !.
norm_goal_to_raw(G, G).
