:- module(control_flow_transformer, [
    analyse_norm_body/2,
    warn_cf_issues/1,
    has_cf_issues/1,
    cf_issue_message/2,
    todo_comment/2,
    construct_preservation_class/2
]).

/** <module> control_flow_transformer — Stage 10: Control Flow Preservation

 * Analyses a normalised Prolog body for control-flow constructs that require
 * special handling during web conversion.  The module classifies every
 * construct as fully preserved, approximately preserved, or not preserved,
 * collects issues that arise from problematic patterns, and provides helpers
 * for emitting print_message warnings and TODO comments in generated code.
 *
 * Preservation semantics
 * ----------------------
 *
 * The following constructs are FULLY PRESERVED by the web converter:
 *
 *   conjunction (norm_conj)
 *       Goal order is maintained exactly.  The left operand executes before
 *       the right operand in every generated handler step.
 *
 *   disjunction (norm_disj)
 *       Each arm becomes an arm of an if-then-else in the generated handler.
 *       The arms are entered in left-to-right order; this matches Prolog's
 *       deterministic first-solution behaviour when there is no backtracking.
 *       Context tag: menu.
 *
 *   if-then-else (norm_if_then_else)
 *       Mapped to (Cond -> ThenGoal ; ElseGoal) in the generated handler.
 *       Deterministic semantics are fully preserved.
 *       Context tag: branch.
 *
 *   if-then (norm_if_then)
 *       Mapped to (Cond -> ThenGoal) in the generated handler, with an
 *       implicit empty else branch (result page with no output).
 *       Context tag: branch.
 *
 *   recursion / retry loop (norm_goal matching ClauseHead)
 *       A direct recursive call to the original predicate is compiled to an
 *       HTTP redirect back to step_0 (retry_resp), preserving the loop
 *       semantics under the assumption that no mutable state is shared
 *       between iterations outside of the HTTP session.
 *       Context tag: loop(F/A).
 *
 * The following constructs are APPROXIMATELY PRESERVED (TODO emitted):
 *
 *   cut (norm_cut) in sequential context
 *       In the original program a bare cut commits to the current clause.
 *       In the generated web handler, there are no choice points to cut
 *       (HTTP handlers are deterministic by design), so the cut has no
 *       observable effect.  A TODO comment is emitted to inform the
 *       developer that the cut semantics have changed.
 *
 *   cut (norm_cut) inside a branch arm (norm_disj / norm_if_then)
 *       In standard Prolog, a cut inside (A ; B) only cuts back to the
 *       disjunction, not beyond it.  In the generated code the cut is
 *       preserved syntactically inside the generated if-then-else branch,
 *       which matches this restricted semantics.  A TODO comment is still
 *       emitted because the wider impact (e.g. cutting past nested
 *       branching) cannot be analysed statically.
 *
 * The following constructs are NOT PRESERVED (warning emitted, no-op or
 * best-effort replacement generated):
 *
 *   exception handling (catch/throw as norm_goal)
 *       catch/3 and throw/1 survive as raw norm_goal/1 calls in the
 *       generated handler.  They will work at the Prolog level but their
 *       interaction with the HTTP server infrastructure is unanalysed.
 *       A warning is printed at conversion time.
 *
 *   negation-as-failure (norm_goal containing \+)
 *       \+(G) passes through as-is.  This is usually safe for pure tests
 *       but may hide unintended solutions if G has side effects.  A warning
 *       is printed when \+ wraps a goal other than a simple test.
 *
 *   dynamic meta-calls (norm_goal containing call/N with unknown functor)
 *       Higher-order calls whose functor is not known at conversion time
 *       (e.g. call(Pred, Arg)) cannot be analysed.  They pass through
 *       unchanged and a warning is emitted.
 *
 * Issue term structure
 * --------------------
 *   issue(Kind, Context, Detail)
 *
 *   Kind    — one of: cut_sequential | cut_in_branch | exception_handling
 *                     | negation_as_failure | dynamic_meta_call
 *   Context — surrounding context atom (sequential | branch | menu | top)
 *   Detail  — additional Prolog term; for cut: norm_cut;
 *              for goals: the raw goal term
 *
 * Usage
 * -----
 *   ?- use_module('src/control_flow_transformer').
 *   ?- analyse_norm_body(Body, Issues).
 *   ?- warn_cf_issues(Issues).
 *   ?- construct_preservation_class(norm_if_then_else(_, _, _), Class).
 *   Class = fully_preserved.
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

:- use_module(library(lists)).

% ==========================================================================
% Public API
% ==========================================================================

%% analyse_norm_body(+NormBody, -Issues) is det.
%
%  Walk NormBody depth-first and collect all control-flow issues into
%  Issues (a list of issue/3 terms).  Issues is [] when no problems are
%  detected.
analyse_norm_body(NormBody, Issues) :-
    walk_body(NormBody, sequential, Issues).

%% warn_cf_issues(+Issues) is det.
%
%  For each issue in Issues emit a SWI-Prolog print_message/2 warning.
%  Does nothing when Issues is [].
warn_cf_issues([]).
warn_cf_issues([Issue | Rest]) :-
    print_message(warning, cf_issue(Issue)),
    warn_cf_issues(Rest).

%% has_cf_issues(+NormBody) is semidet.
%
%  Succeeds when NormBody contains at least one control-flow issue.
has_cf_issues(NormBody) :-
    analyse_norm_body(NormBody, Issues),
    Issues \= [].

%% cf_issue_message(+Issue, -Message) is det.
%
%  Produce a human-readable atom Message describing Issue.
cf_issue_message(issue(cut_sequential, Ctx, _),
    Msg) :-
    atomic_list_concat(
        ['Cut (!) in ', Ctx, ' context: no choice points exist in HTTP handlers; '
        ,'cut has no observable effect (semantics preserved trivially).'],
        Msg).
cf_issue_message(issue(cut_in_branch, Ctx, _),
    Msg) :-
    atomic_list_concat(
        ['Cut (!) inside a ', Ctx, ' branch: cut is preserved syntactically '
        ,'but its cross-branch escape semantics cannot be fully analysed.'],
        Msg).
cf_issue_message(issue(exception_handling, Ctx, Goal),
    Msg) :-
    term_to_atom(Goal, GoalAtom),
    atomic_list_concat(
        ['Exception handling in ', Ctx, ' context: ', GoalAtom,
         ' passes through as-is; interaction with HTTP infrastructure is unverified.'],
        Msg).
cf_issue_message(issue(negation_as_failure, Ctx, Goal),
    Msg) :-
    term_to_atom(Goal, GoalAtom),
    atomic_list_concat(
        ['Negation-as-failure in ', Ctx, ' context: ', GoalAtom,
         ' passes through as-is; safe only when the negated goal is a pure test.'],
        Msg).
cf_issue_message(issue(dynamic_meta_call, Ctx, Goal),
    Msg) :-
    term_to_atom(Goal, GoalAtom),
    atomic_list_concat(
        ['Dynamic meta-call in ', Ctx, ' context: ', GoalAtom,
         ' cannot be statically analysed; passes through unchanged.'],
        Msg).

%% todo_comment(+Issue, -TodoAtom) is det.
%
%  Create a TODO comment atom suitable for embedding as a Prolog comment
%  in generated source code.  TodoAtom begins with "%% TODO:".
todo_comment(Issue, TodoAtom) :-
    cf_issue_message(Issue, Msg),
    atomic_list_concat(['%% TODO: ', Msg], TodoAtom).

%% construct_preservation_class(+Construct, -Class) is det.
%
%  Classify a normalised body construct (the functor, not the full term)
%  with respect to how well its semantics are preserved by the web
%  converter.
%
%  Class is one of:
%    fully_preserved             — semantics identical in web version
%    approximately_preserved(R)  — semantics similar; R is a reason atom
%    not_preserved(R)            — semantics may differ; R is a reason atom
construct_preservation_class(norm_conj(_, _), fully_preserved).
construct_preservation_class(norm_disj(_, _), fully_preserved).
construct_preservation_class(norm_if_then(_, _), fully_preserved).
construct_preservation_class(norm_if_then_else(_, _, _), fully_preserved).
construct_preservation_class(norm_true, fully_preserved).
construct_preservation_class(norm_read_string(_, _, _, _, _), fully_preserved).
construct_preservation_class(norm_read_password(_, _), fully_preserved).
construct_preservation_class(norm_read_password(_), fully_preserved).
construct_preservation_class(norm_output(_), fully_preserved).
construct_preservation_class(norm_cut,
    approximately_preserved(
        'Cut has no effect when HTTP handlers are deterministic')).
construct_preservation_class(norm_goal(catch(_, _, _)),
    not_preserved(
        'Exception handling interaction with HTTP infrastructure is unverified')).
construct_preservation_class(norm_goal(throw(_)),
    not_preserved(
        'Thrown exceptions may not be caught by the HTTP server dispatcher')).
construct_preservation_class(norm_goal(\+(_)),
    approximately_preserved(
        'Negation-as-failure is safe only when the negated goal is a pure test')).
construct_preservation_class(norm_goal(call(_, _)),
    not_preserved('Dynamic meta-calls cannot be statically analysed')).
construct_preservation_class(norm_goal(call(_, _, _)),
    not_preserved('Dynamic meta-calls cannot be statically analysed')).
construct_preservation_class(norm_goal(_), fully_preserved).

% ==========================================================================
% Internal: body walker
% ==========================================================================

%% walk_body(+NormBody, +Context, -Issues) is det.
%
%  Recursively walk NormBody in Context, accumulating issues.
walk_body(norm_conj(A, B), Ctx, Issues) :- !,
    walk_body(A, Ctx, IssA),
    walk_body(B, Ctx, IssB),
    append(IssA, IssB, Issues).

walk_body(norm_disj(A, B), _Ctx, Issues) :- !,
    walk_body(A, menu, IssA),
    walk_body(B, menu, IssB),
    append(IssA, IssB, Issues).

walk_body(norm_if_then(Cond, Then), _Ctx, Issues) :- !,
    walk_body(Cond, branch, IssC),
    walk_body(Then, branch, IssT),
    append(IssC, IssT, Issues).

walk_body(norm_if_then_else(Cond, Then, Else), _Ctx, Issues) :- !,
    walk_body(Cond, branch, IssC),
    walk_body(Then, branch, IssT),
    walk_body(Else, branch, IssE),
    append(IssC, IssT, IssTE),
    append(IssTE, IssE, Issues).

walk_body(norm_cut, Ctx, Issues) :- !,
    ( Ctx = sequential ->
        Issues = [issue(cut_sequential, sequential, norm_cut)]
    ;   Issues = [issue(cut_in_branch, Ctx, norm_cut)]
    ).

walk_body(norm_goal(catch(Goal, Catcher, Recovery)), Ctx, Issues) :- !,
    Issues = [issue(exception_handling, Ctx, catch(Goal, Catcher, Recovery))].

walk_body(norm_goal(throw(E)), Ctx, Issues) :- !,
    Issues = [issue(exception_handling, Ctx, throw(E))].

walk_body(norm_goal(\+(InnerGoal)), Ctx, Issues) :- !,
    ( is_pure_test(InnerGoal) ->
        Issues = []
    ;   Issues = [issue(negation_as_failure, Ctx, \+(InnerGoal))]
    ).

walk_body(norm_goal(call(F, _)), Ctx, Issues) :-
    var(F), !,
    Issues = [issue(dynamic_meta_call, Ctx, call(F, _))].
walk_body(norm_goal(call(F, _, _)), Ctx, Issues) :-
    var(F), !,
    Issues = [issue(dynamic_meta_call, Ctx, call(F, _, _))].

% All other goals (output, true, read, plain norm_goal) are clean.
walk_body(_, _, []).

% ==========================================================================
% Internal: helpers
% ==========================================================================

%% is_pure_test(+Goal) is semidet.
%
%  Succeed when Goal is a recognised pure relational test that has no
%  observable side effects.  Goals that pass this test are safe inside \+.
is_pure_test(_ = _).
is_pure_test(_ \= _).
is_pure_test(_ == _).
is_pure_test(_ \== _).
is_pure_test(_ < _).
is_pure_test(_ > _).
is_pure_test(_ =< _).
is_pure_test(_ >= _).
is_pure_test(_ is _).
is_pure_test(number(_)).
is_pure_test(atom(_)).
is_pure_test(integer(_)).
is_pure_test(float(_)).
is_pure_test(is_list(_)).
is_pure_test(member(_, _)).
is_pure_test(memberchk(_, _)).
is_pure_test(ground(_)).
is_pure_test(var(_)).
is_pure_test(nonvar(_)).
is_pure_test(compound(_)).
is_pure_test(callable(_)).

% ==========================================================================
% SWI-Prolog message hook for print_message/2
% ==========================================================================

:- multifile prolog:message//1.

prolog:message(cf_issue(issue(cut_sequential, Ctx, _))) -->
    { atomic_list_concat(
        ['[vetusiapl2webpl Stage 10] Cut (!) in ', Ctx,
         ' context: cut has no observable effect in HTTP handlers',
         ' (no choice points exist); semantics preserved trivially.'],
        Msg) },
    [ Msg ].

prolog:message(cf_issue(issue(cut_in_branch, Ctx, _))) -->
    { atomic_list_concat(
        ['[vetusiapl2webpl Stage 10] Cut (!) inside ', Ctx,
         ' branch: preserved syntactically.',
         ' Cross-branch escape semantics cannot be fully verified.',
         ' A TODO comment has been added to the generated code.'],
        Msg) },
    [ Msg ].

prolog:message(cf_issue(issue(exception_handling, Ctx, Goal))) -->
    { term_to_atom(Goal, GoalAtom),
      atomic_list_concat(
        ['[vetusiapl2webpl Stage 10] Exception handling (', GoalAtom,
         ') in ', Ctx, ' context: passes through as-is.',
         ' Interaction with the HTTP server is not verified.'],
        Msg) },
    [ Msg ].

prolog:message(cf_issue(issue(negation_as_failure, Ctx, Goal))) -->
    { term_to_atom(Goal, GoalAtom),
      atomic_list_concat(
        ['[vetusiapl2webpl Stage 10] Negation-as-failure (', GoalAtom,
         ') in ', Ctx, ' context: safe only when the negated goal is a pure test.',
         ' Verify that the goal has no side effects.'],
        Msg) },
    [ Msg ].

prolog:message(cf_issue(issue(dynamic_meta_call, Ctx, Goal))) -->
    { term_to_atom(Goal, GoalAtom),
      atomic_list_concat(
        ['[vetusiapl2webpl Stage 10] Dynamic meta-call (', GoalAtom,
         ') in ', Ctx, ' context: cannot be statically analysed.',
         ' Passes through unchanged.'],
        Msg) },
    [ Msg ].
