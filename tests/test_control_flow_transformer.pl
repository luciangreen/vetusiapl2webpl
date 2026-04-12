%% tests/test_control_flow_transformer.pl
%%
%% Unit and semantic-preservation tests for the Stage 10 control-flow
%% transformation module (src/control_flow_transformer.pl).
%%
%% These tests verify:
%%   1. construct_preservation_class/2 correctly classifies every normalised
%%      body form.
%%   2. analyse_norm_body/2 detects known problematic patterns (cut inside
%%      branch, exception handling, negation-as-failure, dynamic meta-calls)
%%      and does not flag clean constructs.
%%   3. has_cf_issues/1 correctly identifies bodies with and without issues.
%%   4. todo_comment/2 generates properly formatted TODO comment atoms.
%%   5. cf_issue_message/2 produces non-empty human-readable descriptions.
%%   6. Semantic preservation: the full Stage 3 + Stage 4 pipeline correctly
%%      preserves the semantics of conjunction, disjunction, if-then-else,
%%      recursion/retry loops, and cut in sequential context.
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_control_flow_transformer.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_control_flow_transformer].
%%   ?- run_tests.

:- use_module('../src/control_flow_transformer').
:- use_module('../src/checkpoint_detector').
:- use_module('../src/continuation_extractor').
:- use_module('../src/reader').
:- use_module(library(plunit)).
:- use_module(library(lists)).

% Capture the test directory at load time for integration tests.
:- prolog_load_context(directory, Dir),
   assert(cft_test_dir(Dir)).

% ==========================================================================
% Helper: build a norm_conj chain from a flat list
% ==========================================================================

list_to_nc([], norm_true).
list_to_nc([G], G) :- !.
list_to_nc([G | Rest], norm_conj(G, Tail)) :-
    list_to_nc(Rest, Tail).

% ==========================================================================
% Tests: construct_preservation_class/2
% ==========================================================================

:- begin_tests(construct_preservation_class).

test(conjunction_is_fully_preserved) :-
    construct_preservation_class(norm_conj(norm_true, norm_true),
                                 fully_preserved).

test(disjunction_is_fully_preserved) :-
    construct_preservation_class(norm_disj(norm_true, norm_true),
                                 fully_preserved).

test(if_then_is_fully_preserved) :-
    construct_preservation_class(norm_if_then(norm_goal(cond), norm_true),
                                 fully_preserved).

test(if_then_else_is_fully_preserved) :-
    construct_preservation_class(
        norm_if_then_else(norm_goal(cond), norm_true, norm_true),
        fully_preserved).

test(norm_true_is_fully_preserved) :-
    construct_preservation_class(norm_true, fully_preserved).

test(norm_output_is_fully_preserved) :-
    construct_preservation_class(norm_output(writeln(hello)), fully_preserved).

test(norm_goal_is_fully_preserved) :-
    construct_preservation_class(norm_goal(foo(x)), fully_preserved).

test(read_string_is_fully_preserved) :-
    construct_preservation_class(norm_read_string(user, "\n", "\r", _, _),
                                 fully_preserved).

test(read_password_2_is_fully_preserved) :-
    construct_preservation_class(norm_read_password('Pw: ', _), fully_preserved).

test(read_password_1_is_fully_preserved) :-
    construct_preservation_class(norm_read_password(_), fully_preserved).

test(cut_is_approximately_preserved) :-
    construct_preservation_class(norm_cut, Class),
    Class = approximately_preserved(_).

test(catch_is_not_preserved) :-
    construct_preservation_class(norm_goal(catch(foo, _, true)), Class),
    Class = not_preserved(_).

test(throw_is_not_preserved) :-
    construct_preservation_class(norm_goal(throw(err)), Class),
    Class = not_preserved(_).

test(negation_is_approximately_preserved) :-
    construct_preservation_class(norm_goal(\+(foo)), Class),
    Class = approximately_preserved(_).

test(meta_call_2_is_not_preserved) :-
    construct_preservation_class(norm_goal(call(_, _)), Class),
    Class = not_preserved(_).

test(meta_call_3_is_not_preserved) :-
    construct_preservation_class(norm_goal(call(_, _, _)), Class),
    Class = not_preserved(_).

:- end_tests(construct_preservation_class).

% ==========================================================================
% Tests: analyse_norm_body/2 — clean bodies produce no issues
% ==========================================================================

:- begin_tests(analyse_clean_bodies).

test(empty_body_no_issues) :-
    analyse_norm_body(norm_true, Issues),
    Issues = [].

test(single_goal_no_issues) :-
    analyse_norm_body(norm_goal(foo), Issues),
    Issues = [].

test(output_goal_no_issues) :-
    analyse_norm_body(norm_output(writeln(hello)), Issues),
    Issues = [].

test(sequential_conjunction_no_issues) :-
    Body = norm_conj(norm_goal(a), norm_goal(b)),
    analyse_norm_body(Body, Issues),
    Issues = [].

test(disjunction_no_issues) :-
    Body = norm_disj(norm_goal(a), norm_goal(b)),
    analyse_norm_body(Body, Issues),
    Issues = [].

test(if_then_else_no_issues) :-
    Body = norm_if_then_else(norm_goal(cond), norm_goal(a), norm_goal(b)),
    analyse_norm_body(Body, Issues),
    Issues = [].

test(if_then_no_issues) :-
    Body = norm_if_then(norm_goal(cond), norm_goal(a)),
    analyse_norm_body(Body, Issues),
    Issues = [].

test(nested_conjunction_no_issues) :-
    list_to_nc([norm_goal(a), norm_goal(b), norm_goal(c)], Body),
    analyse_norm_body(Body, Issues),
    Issues = [].

test(pure_negation_no_issues) :-
    % \+(X = Y) is a pure unification test — should not trigger a warning.
    Body = norm_goal(\+(_ = _)),
    analyse_norm_body(Body, Issues),
    Issues = [].

test(pure_negation_member_no_issues) :-
    Body = norm_goal(\+(member(_, []))),
    analyse_norm_body(Body, Issues),
    Issues = [].

:- end_tests(analyse_clean_bodies).

% ==========================================================================
% Tests: analyse_norm_body/2 — problematic bodies produce issues
% ==========================================================================

:- begin_tests(analyse_problematic_bodies).

%% Bare cut in sequential context produces cut_sequential issue.
test(cut_in_sequential_context) :-
    analyse_norm_body(norm_cut, Issues),
    Issues = [issue(cut_sequential, sequential, norm_cut)].

%% Cut inside a disjunction arm produces cut_in_branch issue.
test(cut_inside_disjunction_arm) :-
    Body = norm_disj(norm_cut, norm_goal(b)),
    analyse_norm_body(Body, Issues),
    member(issue(cut_in_branch, menu, norm_cut), Issues).

%% Cut inside an if-then-else branch produces cut_in_branch issue.
test(cut_inside_if_then_else_then_arm) :-
    Body = norm_if_then_else(norm_goal(cond), norm_cut, norm_goal(b)),
    analyse_norm_body(Body, Issues),
    member(issue(cut_in_branch, branch, norm_cut), Issues).

%% Cut inside an if-then-else else arm produces cut_in_branch issue.
test(cut_inside_if_then_else_else_arm) :-
    Body = norm_if_then_else(norm_goal(cond), norm_goal(a), norm_cut),
    analyse_norm_body(Body, Issues),
    member(issue(cut_in_branch, branch, norm_cut), Issues).

%% Cut inside an if-then body produces cut_in_branch issue.
test(cut_inside_if_then_body) :-
    Body = norm_if_then(norm_goal(cond), norm_cut),
    analyse_norm_body(Body, Issues),
    member(issue(cut_in_branch, branch, norm_cut), Issues).

%% catch/3 produces exception_handling issue.
test(catch_produces_exception_handling_issue) :-
    Body = norm_goal(catch(foo, err, true)),
    analyse_norm_body(Body, Issues),
    Issues = [issue(exception_handling, sequential, catch(foo, err, true))].

%% throw/1 produces exception_handling issue.
test(throw_produces_exception_handling_issue) :-
    Body = norm_goal(throw(my_error)),
    analyse_norm_body(Body, Issues),
    Issues = [issue(exception_handling, sequential, throw(my_error))].

%% \+(impure_goal) produces negation_as_failure issue.
test(negation_impure_goal_produces_issue) :-
    Body = norm_goal(\+(assert(foo))),
    analyse_norm_body(Body, Issues),
    Issues = [issue(negation_as_failure, sequential, \+(assert(foo)))].

%% call/2 with a variable functor produces dynamic_meta_call issue.
test(dynamic_meta_call_var_functor) :-
    Pred = _,
    Body = norm_goal(call(Pred, arg)),
    analyse_norm_body(Body, Issues),
    Issues = [issue(dynamic_meta_call, sequential, call(Pred, arg))].

%% Nested: catch inside a disjunction arm.
test(catch_inside_disj_produces_exception_issue) :-
    Body = norm_disj(
        norm_goal(catch(foo, _, true)),
        norm_goal(b)
    ),
    analyse_norm_body(Body, Issues),
    Issues = [issue(exception_handling, menu, catch(foo, _, true))].

%% Multiple issues in one body are all reported.
test(multiple_issues_collected) :-
    Body = norm_conj(
        norm_cut,
        norm_goal(throw(err))
    ),
    analyse_norm_body(Body, Issues),
    length(Issues, 2),
    member(issue(cut_sequential, sequential, norm_cut), Issues),
    member(issue(exception_handling, sequential, throw(err)), Issues).

:- end_tests(analyse_problematic_bodies).

% ==========================================================================
% Tests: has_cf_issues/1
% ==========================================================================

:- begin_tests(has_cf_issues).

test(clean_body_has_no_issues) :-
    Body = norm_conj(norm_goal(a), norm_goal(b)),
    \+ has_cf_issues(Body).

test(body_with_cut_has_issues) :-
    has_cf_issues(norm_cut).

test(body_with_catch_has_issues) :-
    has_cf_issues(norm_goal(catch(foo, _, true))).

test(body_with_throw_has_issues) :-
    has_cf_issues(norm_goal(throw(err))).

test(nested_issue_detected) :-
    Body = norm_disj(norm_cut, norm_goal(ok)),
    has_cf_issues(Body).

:- end_tests(has_cf_issues).

% ==========================================================================
% Tests: cf_issue_message/2
% ==========================================================================

:- begin_tests(cf_issue_message).

test(cut_sequential_message_is_atom) :-
    cf_issue_message(issue(cut_sequential, sequential, norm_cut), Msg),
    atom(Msg).

test(cut_sequential_message_nonempty) :-
    cf_issue_message(issue(cut_sequential, sequential, norm_cut), Msg),
    Msg \= ''.

test(cut_in_branch_message_is_atom) :-
    cf_issue_message(issue(cut_in_branch, branch, norm_cut), Msg),
    atom(Msg).

test(exception_handling_message_mentions_goal) :-
    cf_issue_message(issue(exception_handling, sequential, catch(foo, _, true)), Msg),
    sub_atom(Msg, _, _, _, 'catch').

test(negation_as_failure_message_is_atom) :-
    cf_issue_message(issue(negation_as_failure, sequential, \+(bar)), Msg),
    atom(Msg).

test(dynamic_meta_call_message_is_atom) :-
    cf_issue_message(issue(dynamic_meta_call, sequential, call(_, _)), Msg),
    atom(Msg).

:- end_tests(cf_issue_message).

% ==========================================================================
% Tests: todo_comment/2
% ==========================================================================

:- begin_tests(todo_comment).

test(todo_comment_starts_with_percent_percent_todo) :-
    Issue = issue(cut_sequential, sequential, norm_cut),
    todo_comment(Issue, Comment),
    sub_atom(Comment, 0, 9, _, '%% TODO: ').

test(todo_comment_for_cut_in_branch_is_atom) :-
    Issue = issue(cut_in_branch, branch, norm_cut),
    todo_comment(Issue, Comment),
    atom(Comment).

test(todo_comment_nonempty) :-
    Issue = issue(exception_handling, sequential, throw(err)),
    todo_comment(Issue, Comment),
    atom_length(Comment, Len),
    Len > 10.

test(todo_comment_mentions_todo) :-
    Issue = issue(cut_in_branch, menu, norm_cut),
    todo_comment(Issue, Comment),
    sub_atom(Comment, _, _, _, 'TODO').

:- end_tests(todo_comment).

% ==========================================================================
% Semantic preservation tests: conjunction order preserved
% ==========================================================================

:- begin_tests(semantic_conjunction).

%% Two reads in conjunction: checkpoints appear left-to-right in source order.
test(conjunction_preserves_checkpoint_order) :-
    V1 = _, V2 = _,
    VN = ['First' = V1, 'Second' = V2],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V1),
          norm_read_string(user, "\n", "\r", _, V2)
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    CPs = [CP1, CP2],
    CP1 = checkpoint(1, _, 'First', _, _, _, _),
    CP2 = checkpoint(2, _, 'Second', _, _, _, _).

%% Goal order within a continuation is preserved: compute goals appear in
%% PreGoals in the same order they appeared in the source body.
test(conjunction_preserves_goal_order_in_pre_goals) :-
    V = _,
    VN = ['X' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_goal(first_compute(V)),
          norm_goal(second_compute(V))
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, PreGoals, _),
    PreGoals = [norm_goal(first_compute(_)), norm_goal(second_compute(_))].

%% Three sequential reads: checkpoints numbered 1, 2, 3.
test(three_reads_give_three_checkpoints) :-
    V1 = _, V2 = _, V3 = _,
    VN = ['A' = V1, 'B' = V2, 'C' = V3],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V1),
          norm_read_string(user, "\n", "\r", _, V2),
          norm_read_string(user, "\n", "\r", _, V3)
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 3),
    maplist([CP]>>(CP = checkpoint(_, _, _, _, _, _, sequential)), CPs).

%% Variables accumulate across steps in conjunction order.
test(conjunction_accumulates_live_vars) :-
    V1 = _, V2 = _,
    VN = ['Name' = V1, 'Age' = V2],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V1),
          norm_read_string(user, "\n", "\r", _, V2),
          norm_output(format("~w ~w~n", [V1, V2]))
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, Steps),
    last(Steps, LastStep),
    LastStep = cont_step(_, RecvVars, _, _),
    memberchk('Name', RecvVars),
    memberchk('Age',  RecvVars).

:- end_tests(semantic_conjunction).

% ==========================================================================
% Semantic preservation tests: disjunction (norm_disj)
% ==========================================================================

:- begin_tests(semantic_disjunction).

%% A disjunction creates at least one checkpoint with menu context.
test(disjunction_creates_menu_context) :-
    V = _,
    VN = ['C' = V],
    Body = norm_disj(
        norm_read_string(user, "\n", "\r", _, V),
        norm_goal(default)
    ),
    detect_checkpoints(Body, VN, CPs),
    member(CP, CPs),
    CP = checkpoint(_, _, _, _, _, _, menu).

%% A disjunction with reads in both arms creates checkpoints for each arm.
test(disjunction_both_arms_detected) :-
    V1 = _, V2 = _,
    VN = ['Left' = V1, 'Right' = V2],
    Body = norm_disj(
        norm_read_string(user, "\n", "\r", _, V1),
        norm_read_string(user, "\n", "\r", _, V2)
    ),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 2).

%% After step generation, a disjunction-sourced step uses cond_resp.
test(disjunction_continuation_is_cond_resp) :-
    V = _,
    VN = ['X' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_disj(norm_goal(branch_a(V)), norm_goal(branch_b(V)))
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, _)).

%% An unconditional disjunction compiles to cond_resp with empty condition.
test(disjunction_compiles_to_cond_resp_empty_cond) :-
    V = _,
    VN = ['X' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_disj(norm_goal(a), norm_goal(b))
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp([], _, _)).

:- end_tests(semantic_disjunction).

% ==========================================================================
% Semantic preservation tests: if-then-else
% ==========================================================================

:- begin_tests(semantic_if_then_else).

%% If-then-else with condition: step compiles to cond_resp with condition.
test(if_then_else_preserves_condition) :-
    V = _,
    VN = ['X' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_if_then_else(
              norm_goal(V = "yes"),
              norm_output(writeln(accepted)),
              norm_output(writeln(rejected))
          )
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(CondGoals, _, _)),
    CondGoals \= [].

%% The condition goals are non-empty (the equality test is preserved).
test(if_then_else_condition_contains_test) :-
    V = _,
    VN = ['Choice' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_if_then_else(
              norm_goal(V = "go"),
              norm_goal(proceed),
              norm_goal(stop)
          )
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp([norm_goal(_=_)], _, _)).

%% Then and else arms each become a result_resp when they contain no reads.
test(if_then_else_arms_are_results) :-
    V = _,
    VN = ['X' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_if_then_else(
              norm_goal(ok(V)),
              norm_output(writeln(yes)),
              norm_output(writeln(no))
          )
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, result_resp(_, _), result_resp(_, _))).

%% if-then (no else) produces an empty else arm in cond_resp.
test(if_then_no_else_has_empty_else) :-
    V = _,
    VN = ['X' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_if_then(
              norm_goal(ok(V)),
              norm_output(writeln(done))
          )
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, result_resp(_, _), result_resp([], _))).

%% Deep nesting: if-then-else inside if-then-else preserves both levels.
test(nested_if_then_else_preserved) :-
    V1 = _, V2 = _,
    VN = ['A' = V1, 'B' = V2],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V1),
          norm_if_then_else(
              norm_goal(V1 = "y"),
              norm_conj(
                  norm_read_string(user, "\n", "\r", _, V2),
                  norm_output(format("A=~w B=~w~n", [V1, V2]))
              ),
              norm_output(writeln(skipped))
          )
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 2),
    extract_continuations(CPs, VN, none, Steps),
    length(Steps, 3).

:- end_tests(semantic_if_then_else).

% ==========================================================================
% Semantic preservation tests: recursion / retry loop
% ==========================================================================

:- begin_tests(semantic_retry_loop).

%% A direct recursive call to the original predicate becomes retry_resp.
test(recursive_call_becomes_retry_resp) :-
    V = _,
    VN = ['X' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_goal(loop)
        ], Body),
    detect_checkpoints(Body, VN, loop/0, CPs),
    extract_continuations(CPs, VN, loop/0, [_, Step1]),
    Step1 = cont_step(step_1, _, _, retry_resp(step_0)).

%% Without ClauseHead = F/A, the same call is NOT a retry.
test(recursive_call_no_head_is_not_retry) :-
    V = _,
    VN = ['X' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_goal(loop)
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, Resp),
    Resp \= retry_resp(_).

%% Retry in the else arm of an if-then-else: else becomes retry_resp.
test(retry_in_else_arm) :-
    V = _,
    VN = ['Choice' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_if_then_else(
              norm_goal(valid(V)),
              norm_output(writeln(ok)),
              norm_goal(retry_pred)
          )
        ], Body),
    detect_checkpoints(Body, VN, retry_pred/0, CPs),
    extract_continuations(CPs, VN, retry_pred/0, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, retry_resp(step_0))).

%% Loop context is assigned to checkpoints inside a branching construct
%% where one arm is the recursive call.
test(loop_context_assigned_in_recursive_branch) :-
    V = _,
    VN = ['X' = V],
    Body = norm_disj(
        norm_conj(
            norm_read_string(user, "\n", "\r", _, V),
            norm_goal(use(V))
        ),
        norm_goal(my_loop)
    ),
    detect_checkpoints(Body, VN, my_loop/0, CPs),
    CPs = [CP],
    CP = checkpoint(_, _, _, _, _, _, loop(my_loop/0)).

%% Retry always redirects to step_0 (the entry handler).
test(retry_target_is_step_0) :-
    V = _,
    VN = ['X' = V],
    Body = norm_conj(
        norm_read_string(user, "\n", "\r", _, V),
        norm_goal(my_p)
    ),
    detect_checkpoints(Body, VN, my_p/0, CPs),
    extract_continuations(CPs, VN, my_p/0, [_, Step1]),
    Step1 = cont_step(step_1, _, _, retry_resp(step_0)).

:- end_tests(semantic_retry_loop).

% ==========================================================================
% Semantic preservation tests: cut handling (Stage 10)
% ==========================================================================

:- begin_tests(semantic_cut_handling).

%% A cut in the middle of a sequential PreGoal list is collected as norm_cut.
test(cut_in_sequential_pre_goals_collected) :-
    V = _,
    VN = ['X' = V],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V),
          norm_cut,
          norm_goal(use(V))
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, PreGoals, _),
    memberchk(norm_cut, PreGoals).

%% A bare norm_cut as the sole remaining body compiles to todo_resp.
test(bare_cut_continuation_is_todo_resp) :-
    V = _,
    VN = ['X' = V],
    Body = norm_conj(
        norm_read_string(user, "\n", "\r", _, V),
        norm_cut
    ),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, todo_resp(_, _)).

%% The fallback response inside a bare-cut todo_resp is result_resp.
test(bare_cut_todo_resp_fallback_is_result) :-
    V = _,
    VN = ['X' = V],
    Body = norm_conj(
        norm_read_string(user, "\n", "\r", _, V),
        norm_cut
    ),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, todo_resp(_, result_resp([], _))).

%% analyse_norm_body on bare cut reports cut_sequential issue.
test(cut_sequential_issue_reported) :-
    analyse_norm_body(norm_cut, Issues),
    memberchk(issue(cut_sequential, sequential, norm_cut), Issues).

%% Cut inside a disjunction arm reports cut_in_branch with menu context.
test(cut_in_disj_arm_reports_cut_in_branch_menu) :-
    Body = norm_disj(norm_cut, norm_goal(other)),
    analyse_norm_body(Body, Issues),
    memberchk(issue(cut_in_branch, menu, norm_cut), Issues).

%% Cut inside an if-then-else branch reports cut_in_branch with branch context.
test(cut_in_ite_branch_reports_cut_in_branch) :-
    Body = norm_if_then_else(norm_goal(c), norm_cut, norm_goal(alt)),
    analyse_norm_body(Body, Issues),
    memberchk(issue(cut_in_branch, branch, norm_cut), Issues).

%% has_cf_issues recognises body with a cut.
test(has_cf_issues_for_cut_body) :-
    has_cf_issues(norm_cut).

:- end_tests(semantic_cut_handling).

% ==========================================================================
% Semantic preservation tests: warnings for unsupported constructs
% ==========================================================================

:- begin_tests(semantic_warnings).

%% catch/3 triggers an exception_handling issue.
test(catch_triggers_exception_handling_issue) :-
    analyse_norm_body(norm_goal(catch(foo, err, true)), Issues),
    Issues = [issue(exception_handling, sequential, catch(foo, err, true))].

%% throw/1 triggers an exception_handling issue.
test(throw_triggers_exception_handling_issue) :-
    analyse_norm_body(norm_goal(throw(my_error)), Issues),
    Issues = [issue(exception_handling, sequential, throw(my_error))].

%% \+(impure) triggers a negation_as_failure issue.
test(impure_negation_triggers_issue) :-
    analyse_norm_body(norm_goal(\+(retract(foo))), Issues),
    Issues = [issue(negation_as_failure, sequential, \+(retract(foo)))].

%% call/2 with variable functor triggers a dynamic_meta_call issue.
test(dynamic_call_triggers_issue) :-
    Pred = _,
    analyse_norm_body(norm_goal(call(Pred, x)), Issues),
    Issues = [issue(dynamic_meta_call, sequential, call(Pred, x))].

%% Issue found inside a nested conjunction.
test(issue_inside_nested_conj_detected) :-
    Body = norm_conj(norm_goal(ok), norm_goal(throw(err))),
    analyse_norm_body(Body, Issues),
    member(issue(exception_handling, _, throw(err)), Issues).

%% Clean body produces no issues (no spurious warnings).
test(no_spurious_warnings_for_clean_body) :-
    Body = norm_conj(
        norm_output(writeln(hello)),
        norm_goal(process)
    ),
    analyse_norm_body(Body, Issues),
    Issues = [].

%% todo_comment generates atom with %% TODO: prefix for cut issue.
test(todo_comment_for_cut_has_prefix) :-
    Issue = issue(cut_in_branch, menu, norm_cut),
    todo_comment(Issue, Comment),
    sub_atom(Comment, 0, 9, _, '%% TODO: ').

%% todo_comment for exception handling mentions 'exception'.
test(todo_comment_for_exception_handling_mentions_exception) :-
    Issue = issue(exception_handling, sequential, catch(_, _, _)),
    todo_comment(Issue, Comment),
    ( sub_atom(Comment, _, _, _, 'Exception')
    ; sub_atom(Comment, _, _, _, 'exception')
    ), !.

:- end_tests(semantic_warnings).

% ==========================================================================
% Integration: semantic preservation on input_example.pl
% ==========================================================================

:- begin_tests(integration_input_example).

%% Load input_example.pl and verify that:
%%   - No control-flow issues are detected (it is a clean sequential program)
%%   - Exactly 2 checkpoints (Name and Age) are detected
%%   - The generated steps preserve variable threading correctly
test(input_example_has_no_cf_issues) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, _VN), NormClauses)),
    \+ has_cf_issues(Body).

test(input_example_two_checkpoints) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 2).

test(input_example_sequential_contexts) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, CPs),
    forall(member(CP, CPs),
           ( CP = checkpoint(_, _, _, _, _, _, sequential) )).

test(input_example_variables_threaded) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, Steps),
    last(Steps, LastStep),
    LastStep = cont_step(_, RecvVars, _, _),
    memberchk('Name', RecvVars),
    memberchk('Age',  RecvVars).

:- end_tests(integration_input_example).

% ==========================================================================
% Helper: resolve path to examples/input_example.pl
% ==========================================================================

input_example_file(File) :-
    cft_test_dir(Dir),
    file_directory_name(Dir, RepoRoot),
    atomic_list_concat([RepoRoot, examples, 'input_example.pl'], '/', File).
