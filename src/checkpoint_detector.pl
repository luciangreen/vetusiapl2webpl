:- module(checkpoint_detector, [
    detect_checkpoints/3,
    detect_checkpoints/4,
    collect_live_vars/3
]).

/** <module> checkpoint_detector — Stage 3: Detection of Web Conversion Points
 *
 * Analyses a normalised Prolog clause body (as produced by the Stage 2
 * reader module) and identifies every input goal — norm_read_string and
 * norm_read_password — as a web-page cut-off point called a *checkpoint*.
 *
 * For each checkpoint the module captures:
 *
 *   • The unique numeric identifier (assigned left-to-right, depth-first).
 *
 *   • The input kind: read_string or read_password.
 *
 *   • The name (atom) of the variable that will receive the user's input,
 *     looked up in the VarNames association list; 'anon' when the variable
 *     has no name.
 *
 *   • The *prompt* goals: norm_output/1 goals accumulated since the previous
 *     checkpoint (or the start of the clause).  These become the HTML content
 *     displayed on the form page.
 *
 *   • The *continuation*: the normalised body that executes after this
 *     checkpoint.  This is expressed in the norm_* representation and
 *     includes the parent continuation when the checkpoint is nested inside
 *     a branch.
 *
 *   • The *live variables*: atom names of variables that were bound by
 *     previous read goals AND appear free in the continuation.  These are
 *     the variables that must be threaded forward as hidden HTML form fields.
 *
 *   • The *context*: the surrounding control-flow structure at the checkpoint.
 *     Possible values:
 *       sequential  — inside a straight-line conjunction
 *       menu        — inside one arm of a disjunction (A ; B)
 *       branch      — inside the Then or Else arm of an if-then(-else)
 *       loop(F/A)   — inside a branch that belongs to a construct where
 *                     another arm contains a recursive call to predicate F/A
 *                     (only produced when the optional ClauseHead argument
 *                     is supplied to detect_checkpoints/4)
 *
 * Checkpoint term structure
 * -------------------------
 *   checkpoint(Id, Kind, VarName, Prompts, Continuation, LiveVars, Context)
 *
 *   Id           — positive integer (1, 2, …)
 *   Kind         — read_string | read_password
 *   VarName      — atom name of the read variable, or 'anon'
 *   Prompts      — list of norm_output/1 goals (in source order)
 *   Continuation — normalised body after this checkpoint
 *   LiveVars     — list of atom names (subset of keys of VarNames)
 *   Context      — sequential | menu | branch | loop(F/A)
 *
 * Usage
 * -----
 *   ?- use_module('src/reader').
 *   ?- use_module('src/checkpoint_detector').
 *   ?- read_and_normalise('examples/input_example.pl', Cs),
 *      member(norm_clause(main, Body, VN), Cs),
 *      detect_checkpoints(Body, VN, CPs).
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

:- use_module(library(lists)).

% ==========================================================================
% Public API
% ==========================================================================

%% detect_checkpoints(+NormBody, +VarNames, -Checkpoints) is det.
%
%  Walk NormBody and return Checkpoints, a list of checkpoint/7 terms in
%  left-to-right, depth-first traversal order.
%
%  VarNames is the Name=Var association list as produced by read_term/3 with
%  the variable_names/1 option and preserved by normalise_clause/3.
%
%  This version performs no loop detection.  Use detect_checkpoints/4 if the
%  clause head is known and loop detection is desired.
detect_checkpoints(NormBody, VarNames, Checkpoints) :-
    detect_checkpoints(NormBody, VarNames, none, Checkpoints).

%% detect_checkpoints(+NormBody, +VarNames, +ClauseHead, -Checkpoints) is det.
%
%  Like detect_checkpoints/3 but also accepts ClauseHead, which is either
%  'none' (no loop detection) or F/A where F is the functor and A the arity
%  of the predicate whose body is being analysed.
%
%  When ClauseHead = F/A, any branching construct (disjunction or
%  if-then-else) that has at least one arm containing a call to F/A will use
%  the context tag loop(F/A) instead of menu/branch for all checkpoints
%  inside that construct.
detect_checkpoints(NormBody, VarNames, ClauseHead, Checkpoints) :-
    norm_to_goal_list(NormBody, GoalList),
    detect_goals(GoalList, norm_true, VarNames, [], [], sequential,
                 ClauseHead, 1, _, Checkpoints).

%% collect_live_vars(+Term, +VarNames, -LiveVarNames) is det.
%
%  Find all variable names from VarNames whose corresponding Prolog variables
%  appear free (uninstantiated) inside Term.
%
%  Term may be any Prolog term, including a normalised body structure.
%  LiveVarNames is a list of atom names — a subset of the keys of VarNames —
%  in the order they appear in VarNames.
collect_live_vars(Term, VarNames, LiveVarNames) :-
    term_variables(Term, FreeVars),
    include(named_var_is_live(FreeVars), VarNames, LivePairs),
    maplist(pair_name, LivePairs, LiveVarNames).

% ==========================================================================
% Internal: goal-list traversal
% ==========================================================================

%% detect_goals(+Goals, +ParentCont, +VN, +BoundVN, +AccPr,
%%              +Ctx, +Head, +IdIn, -IdOut, -CPs) is det.
%
%  Scan a flat list of normalised goals for input checkpoints.
%
%  Goals      — goals at the current conjunction level (flat list)
%  ParentCont — normalised body that follows the entire Goals list in the
%               enclosing context; used to build the full continuation at
%               each checkpoint
%  VN         — full variable-names association list
%  BoundVN    — Name=Var pairs for variables bound by previous read goals
%               (used to compute LiveVars at each checkpoint)
%  AccPr      — accumulated prompt goals (norm_output) since last checkpoint,
%               collected in reverse order and reversed at emission
%  Ctx        — current context tag: sequential | menu | branch | loop(F/A)
%  Head       — none | F/A  — the enclosing clause head for loop detection
%  IdIn       — next checkpoint ID to assign
%  IdOut      — next checkpoint ID after processing Goals
%  CPs        — checkpoints found (output)

detect_goals([], _Parent, _VN, _BVN, _AccPr, _Ctx, _Head, Id, Id, []).

detect_goals([G | Rest], ParentCont, VN, BoundVN, AccPr, Ctx, Head,
             IdIn, IdOut, CPs) :-
    % Build the full continuation for a checkpoint at this position:
    % remaining goals in this list, then the parent continuation.
    goals_to_norm_body(Rest, RestNorm),
    cont_join(RestNorm, ParentCont, Cont),
    (   is_input_goal(G, Kind, Var)
    ->  % ── Input checkpoint ─────────────────────────────────────────────
        var_name_for(Var, VN, VarName),
        find_vn_pair(VarName, VN, NewPair),
        update_bound_vn(VarName, NewPair, BoundVN, BoundVN1),
        collect_live_vars(Cont, BoundVN1, LiveVars),
        reverse(AccPr, Prompts),
        Id1 is IdIn + 1,
        CP = checkpoint(IdIn, Kind, VarName, Prompts, Cont, LiveVars, Ctx),
        CPs = [CP | RestCPs],
        detect_goals(Rest, ParentCont, VN, BoundVN1, [], Ctx, Head,
                     Id1, IdOut, RestCPs)

    ;   G = norm_output(_)
    ->  % ── Output goal — add to prompt accumulator ───────────────────────
        detect_goals(Rest, ParentCont, VN, BoundVN, [G | AccPr], Ctx, Head,
                     IdIn, IdOut, CPs)

    ;   is_branch_goal(G, RawBranches)
    ->  % ── Branching construct — recurse into each branch ─────────────────
        % Determine whether this construct contains a recursive call,
        % and if so override the branch context to loop(F/A).
        pick_branch_context(RawBranches, Head, BranchCtx),
        annotate_branches(RawBranches, BranchCtx, Branches),
        detect_branches(Branches, Cont, VN, BoundVN, AccPr, Head,
                        IdIn, Id2, BranchCPs),
        detect_goals(Rest, ParentCont, VN, BoundVN, [], Ctx, Head,
                     Id2, IdOut, RestCPs),
        append(BranchCPs, RestCPs, CPs)

    ;   % ── Other goal — pass through, keeping accumulated prompts ─────────
        detect_goals(Rest, ParentCont, VN, BoundVN, AccPr, Ctx, Head,
                     IdIn, IdOut, CPs)
    ).

%% detect_branches(+Branches, +Cont, +VN, +BoundVN, +AccPr,
%%                 +Head, +IdIn, -IdOut, -CPs) is det.
%
%  Process a list of branch(NormBody, Context) pairs.
%  Each branch is analysed independently with its own context tag.
%  AccPr (prompts accumulated before the branching construct) is passed into
%  each branch so that prompts from the parent are visible on branch forms.
%  The outer continuation Cont is passed as ParentCont so that checkpoints
%  inside a branch have the correct full continuation.
detect_branches([], _Cont, _VN, _BVN, _AccPr, _Head, Id, Id, []).
detect_branches([branch(Body, BranchCtx) | Rest], Cont, VN, BoundVN, AccPr,
                Head, IdIn, IdOut, CPs) :-
    norm_to_goal_list(Body, GoalList),
    detect_goals(GoalList, Cont, VN, BoundVN, AccPr, BranchCtx, Head,
                 IdIn, Id2, BranchCPs),
    detect_branches(Rest, Cont, VN, BoundVN, AccPr, Head,
                    Id2, IdOut, RestCPs),
    append(BranchCPs, RestCPs, CPs).

% ==========================================================================
% Internal: goal classification
% ==========================================================================

%% is_input_goal(+Goal, -Kind, -Var) is semidet.
%
%  True when Goal is a normalised read goal.
%  Kind is read_string or read_password; Var is the receiving variable.
is_input_goal(norm_read_string(_, _, _, _, V), read_string,  V).
is_input_goal(norm_read_password(_, V),        read_password, V).
is_input_goal(norm_read_password(V),           read_password, V).

%% is_branch_goal(+Goal, -Branches) is semidet.
%
%  True when Goal is a control-flow branching construct.
%  Branches is a list of branch(NormBody, RawCtx) pairs — one per arm.
%  RawCtx is the un-adjusted context before loop-detection override; it is
%  either 'menu' (for a disjunction arm) or 'branch' (for an if-then arm).
%
%  The condition of norm_if_then and norm_if_then_else constructs is NOT
%  scanned for checkpoints because conditions are guard tests, not
%  user-facing interaction points.
is_branch_goal(norm_disj(A, B),
               [branch(A, menu),   branch(B, menu)]).
is_branch_goal(norm_if_then(_Cond, Then),
               [branch(Then, branch)]).
is_branch_goal(norm_if_then_else(_Cond, Then, Else),
               [branch(Then, branch), branch(Else, branch)]).

%% pick_branch_context(+RawBranches, +Head, -Ctx) is det.
%
%  If Head is F/A and any branch body contains a call to F/A, return
%  loop(F/A); otherwise return the raw context from the first branch arm.
pick_branch_context(_RawBranches, none, Ctx) :- !,
    Ctx = sequential.           % placeholder; overridden by annotate_branches
pick_branch_context(RawBranches, F/A, Ctx) :-
    ( any_branch_has_recursive_call(RawBranches, F, A) ->
        Ctx = loop(F/A)
    ;   % Use the context specified in the first arm (menu or branch)
        RawBranches = [branch(_, Ctx) | _]
    ).

%% annotate_branches(+RawBranches, +OverrideCtx, -Branches) is det.
%
%  Replace each branch's context with OverrideCtx when the override was
%  determined by loop detection; otherwise keep the original arm context.
%  When OverrideCtx is sequential (the sentinel used for none-head), restore
%  the original arm contexts.
annotate_branches([], _, []).
annotate_branches([branch(Body, ArmCtx) | Rest], sequential, Branches) :- !,
    % No head given — keep the original arm context (menu or branch).
    Branches = [branch(Body, ArmCtx) | RestB],
    annotate_branches(Rest, sequential, RestB).
annotate_branches([branch(Body, _ArmCtx) | Rest], OverrideCtx, Branches) :-
    Branches = [branch(Body, OverrideCtx) | RestB],
    annotate_branches(Rest, OverrideCtx, RestB).

%% any_branch_has_recursive_call(+Branches, +F, +A) is semidet.
%
%  True when at least one branch body contains a norm_goal(Call) where
%  functor(Call, F, A).
any_branch_has_recursive_call([branch(Body, _) | _], F, A) :-
    norm_body_has_call(Body, F, A), !.
any_branch_has_recursive_call([_ | Rest], F, A) :-
    any_branch_has_recursive_call(Rest, F, A).

%% norm_body_has_call(+NormBody, +F, +A) is semidet.
%
%  True when NormBody contains at least one norm_goal(Call) where
%  the call's principal functor is F/A.
norm_body_has_call(norm_goal(Call), F, A) :-
    functor(Call, F, A), !.
norm_body_has_call(norm_conj(X, Y), F, A) :-
    ( norm_body_has_call(X, F, A) -> true ; norm_body_has_call(Y, F, A) ).
norm_body_has_call(norm_disj(X, Y), F, A) :-
    ( norm_body_has_call(X, F, A) -> true ; norm_body_has_call(Y, F, A) ).
norm_body_has_call(norm_if_then(C, T), F, A) :-
    ( norm_body_has_call(C, F, A) -> true ; norm_body_has_call(T, F, A) ).
norm_body_has_call(norm_if_then_else(C, T, E), F, A) :-
    ( norm_body_has_call(C, F, A) -> true
    ; norm_body_has_call(T, F, A) -> true
    ; norm_body_has_call(E, F, A)
    ).

% ==========================================================================
% Internal: normalised-body / goal-list utilities
% ==========================================================================

%% norm_to_goal_list(+NormBody, -GoalList) is det.
%
%  Flatten the left-spine of a norm_conj tree into a flat list.
%  Non-conjunction goals (including all other norm_* terms) are left as
%  single-element entries in the list.
norm_to_goal_list(norm_conj(A, B), Goals) :- !,
    norm_to_goal_list(A, GA),
    norm_to_goal_list(B, GB),
    append(GA, GB, Goals).
norm_to_goal_list(norm_true, []) :- !.
norm_to_goal_list(G, [G]).

%% goals_to_norm_body(+Goals, -NormBody) is det.
%
%  Convert a flat goal list back into a right-associative norm_conj tree.
goals_to_norm_body([], norm_true).
goals_to_norm_body([G], G) :- !.
goals_to_norm_body([G | Rest], norm_conj(G, RestNorm)) :-
    goals_to_norm_body(Rest, RestNorm).

%% cont_join(+A, +B, -AB) is det.
%
%  Combine two normalised bodies into a sequential composition,
%  simplifying when either operand is norm_true.
cont_join(norm_true, B, B) :- !.
cont_join(A, norm_true, A) :- !.
cont_join(A, B, norm_conj(A, B)).

% ==========================================================================
% Internal: variable utilities
% ==========================================================================

%% var_name_for(+Var, +VN, -Name) is det.
%
%  Look up the atom name of Var in VN (a Name=Var association list).
%  Returns 'anon' when Var is not found.
var_name_for(V, [N = U | _], N) :- V == U, !.
var_name_for(V, [_ | Rest], N) :- var_name_for(V, Rest, N).
var_name_for(_, [], anon).

%% find_vn_pair(+Name, +VN, -Pair) is det.
%
%  Find the Name=Var pair in VN for the given Name.
%  When Name is 'anon' (unnamed variable), returns the sentinel anon=_.
find_vn_pair(anon, _, anon = _) :- !.
find_vn_pair(Name, [Name = V | _], Name = V) :- !.
find_vn_pair(Name, [_ | Rest], Pair) :- find_vn_pair(Name, Rest, Pair).
find_vn_pair(Name, [], Name = _).

%% update_bound_vn(+VarName, +Pair, +BoundVN, -BoundVN1) is det.
%
%  Add Pair to BoundVN unless VarName is 'anon' (anonymous variables are not
%  tracked since they cannot be referenced by name in the continuation).
update_bound_vn(anon, _, BVN, BVN) :- !.
update_bound_vn(_, Pair, BVN, [Pair | BVN]).

%% named_var_is_live(+FreeVars, +Pair) is semidet.
%
%  Helper for include/3 in collect_live_vars/3.
%  Pair is Name=Var; succeeds when Var appears in FreeVars (by identity).
named_var_is_live(FreeVars, _Name = Var) :-
    memberchk_var(Var, FreeVars).

%% memberchk_var(+V, +List) is semidet.
%
%  Like memberchk/2 but uses ==/2 (identity) rather than =/2 (unification),
%  preventing accidental binding of uninstantiated variables.
memberchk_var(V, [U | _]) :- V == U, !.
memberchk_var(V, [_ | T]) :- memberchk_var(V, T).

%% pair_name(+Pair, -Name) is det.
%
%  Extract the key (Name atom) from a Name=Value pair.
pair_name(Name = _, Name).
