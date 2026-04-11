:- module(reader, [
    read_and_normalise/2,
    normalise_clause/3,
    normalise_body/2,
    is_output_goal/1
]).

/** <module> reader — Stage 2: Input Program Reader and Normaliser
 *
 * Reads a Prolog source file and converts it into a normalised internal
 * representation suitable for source-to-source transformation.
 *
 * The normalised representation preserves predicate structure, clause
 * order, and variable names.  Every kind of goal that the converter
 * needs to recognise is tagged with a distinct functor so that later
 * stages can pattern-match without re-interpreting Prolog syntax.
 *
 * Normalised clause forms
 * -----------------------
 *   norm_clause(Head, NormBody, VarNames)
 *       A regular clause (fact or rule).  For a fact the body is
 *       norm_true.  VarNames is the Name=Var association list returned
 *       by read_term/3 with the variable_names/1 option.
 *
 *   directive(Goal)
 *       A top-level directive (:- Goal).
 *
 * Normalised body forms (NormBody)
 * --------------------------------
 *   norm_true                         — true/0 or empty body
 *   norm_cut                          — !
 *   norm_conj(A, B)                   — conjunction  (A , B)
 *   norm_disj(A, B)                   — disjunction  (A ; B)
 *   norm_if_then(Cond, Then)          — soft-cut     (Cond -> Then)
 *   norm_if_then_else(Cond, Then, Else) — if-then-else (Cond -> Then ; Else)
 *   norm_read_string(S, Sents, Pad, Len, Var) — read_string/5
 *   norm_read_password(Prompt, Var)   — read_password/2
 *   norm_read_password(Var)           — read_password/1
 *   norm_output(Goal)                 — terminal output goal
 *   norm_goal(Goal)                   — any other goal
 *
 * Usage
 * -----
 *   ?- use_module('src/reader').
 *   ?- read_and_normalise('examples/input_example.pl', Clauses).
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

:- use_module(library(lists)).

% ==========================================================================
% Public API
% ==========================================================================

%% read_and_normalise(+File:atom, -NormClauses:list) is det.
%
%  Read all terms from File and return a list of normalised representations.
%  Each element is either norm_clause(Head, NormBody, VarNames) or
%  directive(Goal).
read_and_normalise(File, NormClauses) :-
    read_source(File, RawClauses),
    maplist(normalise_pair, RawClauses, NormClauses).

%% normalise_clause(+Term, +VarNames:list, -NormClause) is det.
%
%  Normalise a single raw term into its structured representation.
%
%  Term may be:
%    - a directive   :- Goal       → directive(Goal)
%    - a rule        Head :- Body  → norm_clause(Head, NormBody, VarNames)
%    - a fact        Head          → norm_clause(Head, norm_true, VarNames)
normalise_clause((:- Goal), _VN, directive(Goal)) :- !.
normalise_clause((Head :- Body), VN, norm_clause(Head, NormBody, VN)) :- !,
    normalise_body(Body, NormBody).
normalise_clause(Head, VN, norm_clause(Head, norm_true, VN)).

%% normalise_body(+Body, -NormBody) is det.
%
%  Recursively normalise a clause body into the tagged internal form.
%  Recognised constructs are tagged; all other goals become norm_goal/1.
%
%  Detection order matters: if-then-else must be checked before bare
%  disjunction because (Cond -> Then ; Else) is syntactically a
%  disjunction whose left branch is an if-then.
normalise_body((Cond -> Then ; Else), norm_if_then_else(NC, NT, NE)) :- !,
    normalise_body(Cond, NC),
    normalise_body(Then, NT),
    normalise_body(Else, NE).
normalise_body((A, B), norm_conj(NA, NB)) :- !,
    normalise_body(A, NA),
    normalise_body(B, NB).
normalise_body((A ; B), norm_disj(NA, NB)) :- !,
    normalise_body(A, NA),
    normalise_body(B, NB).
normalise_body((Cond -> Then), norm_if_then(NC, NT)) :- !,
    normalise_body(Cond, NC),
    normalise_body(Then, NT).
normalise_body(!, norm_cut) :- !.
normalise_body(true, norm_true) :- !.
normalise_body(read_string(S, Sents, Pad, Len, V),
               norm_read_string(S, Sents, Pad, Len, V)) :- !.
normalise_body(read_password(Prompt, V), norm_read_password(Prompt, V)) :- !.
normalise_body(read_password(V),         norm_read_password(V)) :- !.
normalise_body(Goal, norm_output(Goal)) :-
    is_output_goal(Goal), !.
normalise_body(Goal, norm_goal(Goal)).

%% is_output_goal(+Goal) is semidet.
%
%  True when Goal is a recognised terminal-output predicate.
is_output_goal(writeln(_)).
is_output_goal(write(_)).
is_output_goal(nl).
is_output_goal(format(_, _)).
is_output_goal(format(_)).
is_output_goal(writef(_, _)).
is_output_goal(print(_)).

% ==========================================================================
% Internal: file reading
% ==========================================================================

%% read_source(+File:atom, -Clauses:list) is det.
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

% --------------------------------------------------------------------------
% Internal helpers
% --------------------------------------------------------------------------

normalise_pair((Term, VN), Norm) :-
    normalise_clause(Term, VN, Norm).
