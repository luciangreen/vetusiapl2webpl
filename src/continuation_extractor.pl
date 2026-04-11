:- module(continuation_extractor, [
    extract_continuations/4,
    write_cont_steps/3,
    cont_step_name/2
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
 *   StepName     — atom: handler predicate name (step_0, step_1, …)
 *   RecvVarNames — list of atom names: variables received via http_parameters/2
 *   PreGoals     — list of norm_goal/1 terms to execute before rendering
 *   Response     — response term (see below)
 *
 * Response terms
 * --------------
 *   form_resp(Prompts, InputVarName, HiddenVarNames, NextStep)
 *       Render an HTML form.
 *       Prompts        — list of norm_output/1 goals shown on the form page
 *       InputVarName   — atom: the text-input field name (variable being read)
 *       HiddenVarNames — list of atom names to carry forward as hidden fields
 *       NextStep       — atom: the next handler name
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
 *       TargetStep — atom: entry handler to redirect to (always step_0)
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

% ==========================================================================
% Public API
% ==========================================================================

%% cont_step_name(+Index:integer, -Name:atom) is det.
%
%  Map a step index (0, 1, 2, …) to its handler atom name.
%  step_0 is the entry GET handler; step_1 onward are POST handlers.
cont_step_name(0, step_0) :- !.
cont_step_name(N, Name) :-
    atom_concat(step_, N, Name).

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
%                compiled to retry_resp(step_0).
%  Steps       — result: list of cont_step/4 terms
extract_continuations([], _VN, _Head, []) :- !.
extract_continuations(Checkpoints, VN, Head, Steps) :-
    Checkpoints = [FirstCP | _],
    FirstCP = checkpoint(_, _, FirstVarName, FirstPrompts, _, FirstLiveVars, _),
    % step_0: entry GET handler — no parameters received.
    % The hidden vars for the form = LiveVars of FirstCP minus FirstVarName
    % (those are carried forward to step_1; but step_1 = FirstCP's step, and
    %  since it's the first checkpoint, no vars were bound before it, so
    %  HiddenVars0 is typically empty).
    exclude(==(FirstVarName), FirstLiveVars, HiddenVars0),
    cont_step_name(1, FirstNextStep),
    Step0 = cont_step(step_0, [], [],
                      form_resp(FirstPrompts, FirstVarName, HiddenVars0, FirstNextStep)),
    % Generate steps 1..N from each checkpoint.
    gen_cont_steps(Checkpoints, VN, Head, ContSteps),
    Steps = [Step0 | ContSteps].

%% write_cont_steps(+Out:stream, +Steps:list, +VarNames:list) is det.
%
%  Write the complete generated web program — boilerplate, HTTP handler
%  declarations, server init, and one handler clause per cont_step —
%  to the open output stream Out.
write_cont_steps(Out, Steps, VN) :-
    emit_ce_header_comment(Out),
    emit_ce_use_modules(Out),
    nl(Out),
    emit_ce_handler_decls(Out, Steps),
    nl(Out),
    emit_ce_server_init(Out),
    nl(Out),
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
    cont_step_name(Id, StepName),
    % Determine how many checkpoints lie within this continuation body.
    % These are the first NCont elements of RestCPs (depth-first order is
    % preserved by Stage 3, so positional slicing works correctly).
    count_reads_in_body(Continuation, NCont),
    ce_take_n(NCont, RestCPs, ContCPs),
    % Split the continuation body: collect leading compute goals as PreGoals
    % and leave the rest for Response compilation.
    collect_pre_goals(Continuation, PreGoals, RemBody),
    % Compile the remaining body into a Response term.
    compile_cont_body(RemBody, LiveVars, ContCPs, VN, Head, Response),
    Step = cont_step(StepName, LiveVars, PreGoals, Response),
    gen_cont_steps(RestCPs, VN, Head, RestSteps).

%% collect_pre_goals(+NormBody, -PreGoals, -RemBody) is det.
%
%  Walk NormBody left-to-right collecting leading norm_goal/1 goals into
%  PreGoals (these are compute goals to execute before rendering HTML).
%  norm_output/1 goals are skipped silently — they are already captured in
%  the next checkpoint's Prompts field and will be emitted there.
%  Stops at the first norm_read_*, norm_if_then_else, norm_disj, or norm_if_then.
collect_pre_goals(norm_conj(norm_goal(G), Rest), [norm_goal(G) | More], RemBody) :- !,
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
%  Response — form_resp | result_resp | cond_resp | retry_resp

% Empty / true body → result page with nothing to show.
compile_cont_body(norm_true, LiveVars, _ContCPs, _VN, _Head,
                  result_resp([], LiveVars)) :- !.

% norm_cut (bare cut) → treat as empty result.
compile_cont_body(norm_cut, LiveVars, _ContCPs, _VN, _Head,
                  result_resp([], LiveVars)) :- !.

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
                  retry_resp(step_0)) :-
    Head \= none,
    Head = F/A,
    functor(Call, F, A), !.

% A body with no reads that contains a recursive call somewhere → retry.
% (Handles cases like norm_conj(norm_output(invalid), norm_goal(main)).)
compile_cont_body(NormBody, _LiveVars, _ContCPs, _VN, Head,
                  retry_resp(step_0)) :-
    Head \= none,
    Head = F/A,
    \+ contains_read_in_body(NormBody),
    ce_body_has_call(NormBody, F, A), !.

% Body contains at least one read — generate form_resp using the first
% remaining checkpoint (ContCPs head) to get the prompts and input var.
compile_cont_body(NormBody, _LiveVars, [NextCP | _], _VN, _Head,
                  form_resp(Prompts, InputVarName, HiddenVarNames, NextStep)) :-
    contains_read_in_body(NormBody), !,
    NextCP = checkpoint(Id, _, InputVarName, Prompts, _, NextLiveVars, _),
    % Hidden vars = what step_{Id} receives minus the var it is about to read.
    exclude(==(InputVarName), NextLiveVars, HiddenVarNames),
    cont_step_name(Id, NextStep).

% Terminal body with no reads and no retry — result page.
compile_cont_body(NormBody, LiveVars, _ContCPs, _VN, _Head,
                  result_resp(Goals, LiveVars)) :-
    ce_norm_to_goal_list(NormBody, Goals).

% ==========================================================================
% Internal: body analysis utilities
% ==========================================================================

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
    format(Out, ":- http_handler(root(.), step_0, []).~n", []),
    include(is_post_step, Steps, PostSteps),
    maplist(emit_ce_handler_decl(Out), PostSteps).

is_post_step(cont_step(Name, _, _, _)) :- Name \= step_0.

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
write_cont_step(Out, VN, cont_step(StepName, RecvVarNames, PreGoals, Response)) :-
    % Request variable: underscore-prefixed for step_0 (never used),
    % plain for all POST steps (passed to http_parameters/2 and http_redirect/3).
    ( StepName = step_0 -> ReqAtom = '_Request' ; ReqAtom = 'Request' ),
    ExtVN = [ReqAtom = ReqVar | VN],
    % Build the full clause body as a Prolog term, then write it.
    build_params_goal(RecvVarNames, ReqVar, VN, ParamsGoal),
    maplist(norm_goal_to_call, PreGoals, PreCalls),
    response_to_goal(Response, ReqVar, VN, RespGoal),
    ce_goals_to_conj([ParamsGoal | PreCalls], PreConj),
    ( PreConj = true ->
        Body = RespGoal
    ;   Body = (PreConj, RespGoal)
    ),
    Head =.. [StepName, ReqVar],
    Clause = (Head :- Body),
    nl(Out),
    % write_term preserves variable names from ExtVN.
    write_term(Out, Clause, [variable_names(ExtVN), quoted(true)]),
    format(Out, ".~n", []).

%% build_params_goal(+VarNames, +ReqVar, +VN, -Goal) is det.
%
%  Build the http_parameters/2 goal for the given variable names.
%  Returns 'true' when the list is empty (step_0 has no parameters).
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

%% response_to_goal(+Response, +ReqVar, +VN, -Goal) is det.
%
%  Convert a Response term into a Prolog goal term suitable for
%  inclusion in a handler clause body.
response_to_goal(form_resp(Prompts, InputVarName, HiddenVarNames, NextStep),
                 _ReqVar, VN, Goal) :-
    atom_concat('/', NextStep, Action),
    maplist(make_hidden_input_term(VN), HiddenVarNames, HiddenInputs),
    maplist(norm_output_to_html_term, Prompts, PromptHtmls),
    TextInput   = input([type=text,   name=InputVarName]),
    SubmitInput = input([type=submit, value='Next']),
    append(HiddenInputs, PromptHtmls, Acc),
    append(Acc, [TextInput, SubmitInput], FormChildren),
    Form      = form([method=post, action=Action], FormChildren),
    Goal      = reply_html_page(title('Form'), [Form]).

response_to_goal(result_resp(Goals, _LiveVars), _ReqVar, _VN, Goal) :-
    maplist(norm_to_result_call, Goals, Lines),
    ce_goals_to_conj(
        [ format('Content-type: text/html\n\n'),
          format('<html><body>\n')
        | Lines
        ],
        PreGoal),
    LastGoal = format('</body></html>\n'),
    ( PreGoal = true ->
        Goal = LastGoal
    ;   Goal = (PreGoal, LastGoal)
    ).

response_to_goal(cond_resp([], ThenResp, ElseResp), ReqVar, VN, Goal) :- !,
    response_to_goal(ThenResp, ReqVar, VN, ThenGoal),
    response_to_goal(ElseResp, ReqVar, VN, ElseGoal),
    Goal = (ThenGoal ; ElseGoal).

response_to_goal(cond_resp(CondGoals, ThenResp, ElseResp), ReqVar, VN, Goal) :-
    % CondGoals are norm_goal/1 terms; unwrap to raw Prolog goals before
    % building the conjunction that appears in the if-then-else condition.
    maplist(norm_goal_to_raw, CondGoals, RawCondGoals),
    ce_goals_to_conj(RawCondGoals, Cond),
    response_to_goal(ThenResp, ReqVar, VN, ThenGoal),
    response_to_goal(ElseResp, ReqVar, VN, ElseGoal),
    ( Cond = true ->
        Goal = (ThenGoal ; ElseGoal)
    ;   Goal = (Cond -> ThenGoal ; ElseGoal)
    ).

response_to_goal(retry_resp(_TargetStep), ReqVar, _VN, Goal) :-
    Goal = http_redirect(see_other, root(.), ReqVar).

% ==========================================================================
% Internal: HTML / output helpers
% ==========================================================================

%% make_hidden_input_term(+VN, +VarName, -InputTerm) is det.
%
%  Build an input([type=hidden, name=VarName, value=Var]) term.
make_hidden_input_term(VN, VarName, input([type=hidden, name=VarName, value=Var])) :-
    ce_find_var(VarName, VN, Var).

%% norm_output_to_html_term(+NormOutput, -HtmlTerm) is det.
%
%  Convert a norm_output/1 goal to an HTML term for reply_html_page/2.
norm_output_to_html_term(norm_output(writeln(X)), p(X))                    :- !.
norm_output_to_html_term(norm_output(write(X)),   span(X))                  :- !.
norm_output_to_html_term(norm_output(nl),          br([]))                  :- !.
norm_output_to_html_term(norm_output(print(X)),    p(X))                    :- !.
norm_output_to_html_term(norm_output(format(Fmt, Args)),
                         p(runtime_format(Fmt, Args)))                      :- !.
norm_output_to_html_term(norm_output(format(Fmt)), p(Fmt))                  :- !.
norm_output_to_html_term(_,                        p(''))                   .

%% norm_to_result_call(+NormGoal, -Call) is det.
%
%  Convert a normalised goal to a format/2 call suitable for a result page,
%  or pass through compute goals unchanged.
norm_to_result_call(norm_output(writeln(X)),       format('<p>~w</p>\n',  [X])) :- !.
norm_to_result_call(norm_output(write(X)),         format('<span>~w</span>', [X])) :- !.
norm_to_result_call(norm_output(nl),               format('<br/>\n'))            :- !.
norm_to_result_call(norm_output(format(Fmt, Args)), format(Fmt, Args))           :- !.
norm_to_result_call(norm_output(format(Fmt)),       format(Fmt))                 :- !.
norm_to_result_call(norm_output(print(X)),         format('<p>~w</p>\n',  [X])) :- !.
norm_to_result_call(norm_goal(G), G)                                             :- !.
norm_to_result_call(_, format('<!-- goal -->\n')).

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
