:- module(state_serialiser, [
    state_serialise/2,
    state_deserialise/2,
    emit_state_serialiser_helpers/1
]).

/** <module> state_serialiser — Stage 8: State Serialisation / Deserialisation
 *
 * Provides safe round-trip serialisation of Prolog terms to atoms suitable
 * for transport through HTML hidden form fields.
 *
 * The serialiser uses SWI-Prolog's built-in term_to_atom/2 predicate, which
 * writes terms with quoted(true) so that every term class (atoms, integers,
 * floats, lists, strings, compound terms) produces a parseable atom that
 * can be decoded back to the original term without loss of type or structure.
 *
 * Two predicates are provided:
 *
 *   state_serialise(+Term, -Atom)
 *       Convert any ground Prolog term to its canonical atom representation.
 *       The atom is safe to use as an HTML form field value (html_write
 *       will HTML-escape any special characters in the attribute value,
 *       and SWI-Prolog's HTTP library URL-encodes/decodes transparently).
 *
 *   state_deserialise(+Atom, -Term)
 *       Parse a previously serialised atom back to its original Prolog term.
 *       If the atom is not a well-formed Prolog term (e.g. user-typed text
 *       containing spaces such as "Hello World"), parsing is caught and the
 *       atom is returned as-is so that plain string inputs are never lost.
 *
 * Round-trip guarantee
 * --------------------
 * For every ground term T:
 *   state_serialise(T, A), state_deserialise(A, T2)  ⇒  T2 == T
 *
 * This holds for:
 *   • atoms             — hello, 'Hello World', 'it''s'
 *   • integers          — 0, 42, -7
 *   • floats            — 3.14, -0.5
 *   • SWI strings       — "hello", ""
 *   • lists             — [], [1,2,3], [[a,b],[c,d]]
 *   • compound terms    — foo(bar), f(1, g(2))
 *
 * Fallback behaviour
 * ------------------
 * state_deserialise/2 falls back to returning the raw atom when the input
 * is not a syntactically valid Prolog term.  This preserves arbitrary
 * user-typed text (e.g. "Hello World") that passes through http_parameters
 * as-is without requiring the user to type quoted Prolog syntax.
 *
 * Emitting helpers into generated programs
 * -----------------------------------------
 * emit_state_serialiser_helpers/1 writes Prolog source definitions for both
 * predicates into an open output stream, so the generated web program is
 * self-contained and does not depend on this module being present at the
 * deployment site.
 *
 * Usage
 * -----
 *   ?- use_module('src/state_serialiser').
 *   ?- state_serialise([1,2,3], A).
 *   A = '[1,2,3]'.
 *   ?- state_deserialise('[1,2,3]', T).
 *   T = [1, 2, 3].
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

% ==========================================================================
% Runtime predicates
% ==========================================================================

%% state_serialise(+Term, -Atom) is det.
%
%  Serialise Term to a canonical atom representation using term_to_atom/2.
%  The resulting Atom:
%    • is a valid Prolog term when parsed back with term_to_atom/2
%    • is safe for use as an HTML form hidden-field value (html_write
%      escapes any embedded HTML special characters in the attribute)
%    • correctly distinguishes atoms from integers ('42' vs 42) because
%      quoted(true) quoting is applied by write_term internally
state_serialise(Term, Atom) :-
    term_to_atom(Term, Atom).

%% state_deserialise(+Atom, -Term) is det.
%
%  Parse a serialised atom back to its original Prolog term.
%
%  Success cases:
%    • Atom is a valid Prolog term string  →  Term is the parsed value
%
%  Fallback case (always succeeds):
%    • Atom is not a valid Prolog term    →  Term = Atom (identity)
%
%  The fallback handles user-typed text that was received via http_parameters
%  without going through state_serialise first (e.g. the contents of a text
%  input field typed as "Hello World", which is not a valid Prolog term).
state_deserialise(Atom, Term) :-
    ( catch(term_to_atom(Term, Atom), _, fail) ->
        true
    ;   Term = Atom
    ).

% ==========================================================================
% Emitting runtime helper definitions into generated programs
% ==========================================================================

%% emit_state_serialiser_helpers(+Out:stream) is det.
%
%  Write Prolog source definitions for state_serialise/2 and
%  state_deserialise/2 into the open output stream Out.  These definitions
%  are embedded in every generated web program so the program is
%  self-contained.
emit_state_serialiser_helpers(Out) :-
    nl(Out),
    format(Out, "%% --------------------------------------------------~n", []),
    format(Out, "%% State serialisation helpers (Stage 8)~n", []),
    format(Out, "%% --------------------------------------------------~n~n", []),
    format(Out, "state_serialise(Term, Atom) :-~n", []),
    format(Out, "    term_to_atom(Term, Atom).~n~n", []),
    format(Out, "state_deserialise(Atom, Term) :-~n", []),
    format(Out, "    ( catch(term_to_atom(Term, Atom), _, fail) ->~n", []),
    format(Out, "        true~n", []),
    format(Out, "    ;   Term = Atom~n", []),
    format(Out, "    ).~n~n", []).
