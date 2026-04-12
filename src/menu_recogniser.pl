:- module(menu_recogniser, [
    is_menu_checkpoint/4,
    extract_menu_choices/4,
    menu_input_kind/2
]).

/** <module> menu_recogniser — Stage 9: Menu Pattern Detection

 * Detects terminal-style menu patterns in normalised Prolog bodies and
 * extracts structured choice lists for use by the menu-to-form converter.
 *
 * A *menu checkpoint* is a read_string checkpoint whose:
 *   1. Prompts contain at least one numbered item (text starting with a
 *      digit followed by '.'), such as "1. Register" or "2. Login".
 *   2. Continuation body is a chain of if-then-else tests that compare
 *      the read variable against ground literal values ("1", "2", …).
 *
 * Exported predicates
 * -------------------
 *
 *   is_menu_checkpoint(+CP, +VN, -Choices, -InvalidAction) is semidet.
 *       Succeeds when the checkpoint CP matches the menu pattern.
 *       Choices      — list of menu_choice(Value, Label) terms in order.
 *       InvalidAction — retry (the final else arm contains a recursive call)
 *                       or none (the final else arm is output-only or empty).
 *
 *   extract_menu_choices(+NormBody, +ChoiceVar, -Choices, -InvalidAction) is semidet.
 *       Walk the top-level if-then-else chain in NormBody extracting each
 *       arm where the condition is ChoiceVar = Literal (or Literal = ChoiceVar
 *       or using ==/2).  Choices is a list of menu_choice(Value, Value)
 *       placeholders; labels are filled in by is_menu_checkpoint from Prompts.
 *
 *   menu_input_kind(+Choices, -InputKind) is det.
 *       Choose an HTML input widget based on the number of choices.
 *       Up to 4 choices → radio; 5 or more → select.
 *
 * menu_choice term structure
 * --------------------------
 *   menu_choice(Value, Label)
 *       Value — the literal compared in the if-then-else condition
 *               (atom, string, or integer; e.g. "1", '1', or 1)
 *       Label — human-readable label string/atom; derived from a matching
 *               prompt (e.g. '1. Register') or falls back to the Value.
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

:- use_module(library(lists)).

% ==========================================================================
% Public API
% ==========================================================================

%% is_menu_checkpoint(+CP, +VN, -Choices, -InvalidAction) is semidet.
%
%  Succeed when CP is a menu-style checkpoint.
%  CP     — checkpoint/7 term from Stage 3
%  VN     — Name=Var association list from read_term/3
%  Choices       — list of menu_choice(Value, Label)
%  InvalidAction — retry | none
is_menu_checkpoint(
        checkpoint(_Id, read_string, VarName, Prompts, Cont, _Live, _Ctx),
        VN, Choices, InvalidAction) :-
    VarName \= anon,
    mr_prompts_have_numbered_item(Prompts),
    mr_find_var(VarName, VN, Var),
    extract_menu_choices(Cont, Var, Choices0, InvalidAction),
    Choices0 \= [],
    enrich_choices_with_labels(Choices0, Prompts, Choices).

%% extract_menu_choices(+NormBody, +ChoiceVar, -Choices, -InvalidAction) is semidet.
%
%  Walk the top-level if-then-else chain in NormBody.
%  Each arm whose condition tests ChoiceVar against a literal contributes a
%  menu_choice/2 placeholder (Value, Value) to Choices.
%  The final else arm determines InvalidAction.
extract_menu_choices(norm_if_then_else(Cond, _Then, Else),
                     ChoiceVar,
                     [menu_choice(Value, Value) | Rest],
                     InvalidAction) :-
    mr_is_var_eq_cond(Cond, ChoiceVar, Value),
    !,
    extract_menu_choices(Else, ChoiceVar, Rest, InvalidAction).
extract_menu_choices(FinalElse, _ChoiceVar, [], InvalidAction) :-
    ( mr_body_has_any_goal(FinalElse) ->
        InvalidAction = retry
    ;
        InvalidAction = none
    ).

%% menu_input_kind(+Choices, -InputKind) is det.
%
%  Select the HTML widget type based on the number of available choices.
%  1–4 choices → radio buttons.
%  5 or more choices → select (dropdown).
menu_input_kind(Choices, radio) :-
    length(Choices, N),
    N =< 4,
    !.
menu_input_kind(_Choices, select).

% ==========================================================================
% Internal: prompt analysis
% ==========================================================================

%% mr_prompts_have_numbered_item(+Prompts) is semidet.
%
%  True when at least one prompt's text starts with a digit ('0'–'9').
%  Used as a primary signal that a read checkpoint is a numbered menu.
mr_prompts_have_numbered_item(Prompts) :-
    member(norm_output(Goal), Prompts),
    mr_prompt_atom(Goal, Text),
    atom(Text),
    atom_codes(Text, [First | _]),
    First >= 0'0,
    First =< 0'9,
    !.

%% mr_prompt_atom(+Goal, -Text) is semidet.
%
%  Extract the ground text atom from a normalised output goal.
mr_prompt_atom(writeln(T), T) :- atom(T), !.
mr_prompt_atom(write(T),   T) :- atom(T), !.
mr_prompt_atom(print(T),   T) :- atom(T), !.
mr_prompt_atom(format(Fmt), Fmt) :- atom(Fmt), !.
mr_prompt_atom(format(Fmt, _), Fmt) :- atom(Fmt), !.

% ==========================================================================
% Internal: condition analysis
% ==========================================================================

%% mr_is_var_eq_cond(+Cond, +ChoiceVar, -Value) is semidet.
%
%  True when Cond is a normalised goal testing ChoiceVar against a ground
%  literal Value using unification (=/2) or strict equality (==/2).
%  Both orderings (Var = Value and Value = Var) are recognised.
mr_is_var_eq_cond(norm_goal(Var = Value), ChoiceVar, Value) :-
    Var == ChoiceVar,
    mr_is_literal(Value),
    !.
mr_is_var_eq_cond(norm_goal(Value = Var), ChoiceVar, Value) :-
    Var == ChoiceVar,
    mr_is_literal(Value),
    !.
mr_is_var_eq_cond(norm_goal(Var == Value), ChoiceVar, Value) :-
    Var == ChoiceVar,
    mr_is_literal(Value),
    !.
mr_is_var_eq_cond(norm_goal(Value == Var), ChoiceVar, Value) :-
    Var == ChoiceVar,
    mr_is_literal(Value).

%% mr_is_literal(+Value) is semidet.
%
%  True when Value is a ground scalar: atom, string, or integer.
mr_is_literal(V) :- atom(V),    !.
mr_is_literal(V) :- string(V),  !.
mr_is_literal(V) :- integer(V).

% ==========================================================================
% Internal: goal presence check
% ==========================================================================

%% mr_body_has_any_goal(+NormBody) is semidet.
%
%  True when NormBody contains at least one norm_goal/1 term (a non-output
%  Prolog call).  Used to classify the final else arm as retry (when a
%  recursive call is present) or none (when only output or empty).
mr_body_has_any_goal(norm_goal(_)) :- !.
mr_body_has_any_goal(norm_conj(A, B)) :-
    ( mr_body_has_any_goal(A) -> true ; mr_body_has_any_goal(B) ).
mr_body_has_any_goal(norm_if_then(_, T)) :-
    mr_body_has_any_goal(T).
mr_body_has_any_goal(norm_if_then_else(_, T, E)) :-
    ( mr_body_has_any_goal(T) -> true ; mr_body_has_any_goal(E) ).
mr_body_has_any_goal(norm_disj(A, B)) :-
    ( mr_body_has_any_goal(A) -> true ; mr_body_has_any_goal(B) ).

% ==========================================================================
% Internal: label enrichment
% ==========================================================================

%% enrich_choices_with_labels(+Choices0, +Prompts, -Choices) is det.
%
%  For each menu_choice(Value, _) placeholder in Choices0, find a matching
%  numbered prompt in Prompts (a prompt whose text starts with ValueAtom
%  followed by '.') and use it as the label.  When no matching prompt is
%  found the label falls back to ValueAtom.
enrich_choices_with_labels([], _Prompts, []).
enrich_choices_with_labels([menu_choice(Value, _) | Rest], Prompts,
                            [menu_choice(Value, Label) | RestOut]) :-
    ( find_label_for_value(Value, Prompts, FoundLabel) ->
        Label = FoundLabel
    ;
        mr_value_to_atom(Value, Label)
    ),
    enrich_choices_with_labels(Rest, Prompts, RestOut).

%% find_label_for_value(+Value, +Prompts, -Label) is semidet.
%
%  Search Prompts for a writeln/write/format goal whose text starts with
%  the digit prefix derived from Value (e.g. "1." for Value = "1").
find_label_for_value(Value, Prompts, Label) :-
    mr_value_to_atom(Value, ValueAtom),
    atom_concat(ValueAtom, '.', Prefix),
    member(norm_output(Goal), Prompts),
    mr_prompt_atom(Goal, Text),
    atom(Text),
    sub_atom(Text, 0, _, _, Prefix),
    !,
    Label = Text.

%% mr_value_to_atom(+Value, -Atom) is det.
%
%  Convert a literal value (atom, string, integer) to a plain atom for
%  display and prefix matching.
mr_value_to_atom(V, V)    :- atom(V),    !.
mr_value_to_atom(V, A)    :- string(V),  !, atom_string(A, V).
mr_value_to_atom(V, A)    :- integer(V), !, atom_number(A, V).

%% mr_find_var(+Name, +VN, -Var) is semidet.
%
%  Look up the Prolog variable for Name in the Name=Var association list VN.
mr_find_var(Name, [Name = V | _], V) :- !.
mr_find_var(Name, [_ | Rest], V) :-
    mr_find_var(Name, Rest, V).
