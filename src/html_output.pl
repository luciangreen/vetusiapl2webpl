:- module(html_output, [
    % HTML fragment detection
    looks_like_html/1,
    % HTML escaping utility
    html_escape/2,
    % Converter-side helpers (used during code generation)
    norm_output_to_html_term/2,
    norm_output_to_result_call/2,
    % Emitter: write runtime helper definitions into a generated file
    emit_html_helpers/1,
    % Emitter: write a use_module(web_support) loader line (Stage 11)
    emit_web_support_loader/1,
    % Runtime helpers — page wrapper
    html_page_header/1,
    html_page_footer/0,
    % Runtime helpers — line / inline output
    html_writeln/1,
    html_write/1,
    % Runtime helpers — safe (escaped) output
    html_safe_writeln/1,
    html_safe_write/1
]).

/** <module> html_output — Stage 6: HTML Output Conversion
 *
 * Converts terminal-output goals into HTML output calls and provides
 * helper predicates for use in generated web programs.
 *
 * Two kinds of predicates are defined here:
 *
 *   1. **Converter-side** predicates (run during code generation):
 *        norm_output_to_html_term/2  — convert a norm_output/1 goal to an
 *                                      HTML term suitable for reply_html_page/2
 *        norm_output_to_result_call/2 — convert a norm_output/1 goal to a
 *                                       Prolog call suitable for a result page
 *        emit_html_helpers/1         — write runtime helper definitions into
 *                                      an output stream (for inclusion in
 *                                      generated programs)
 *
 *   2. **Runtime** predicates (available in generated programs):
 *        html_page_header/1          — emit Content-type header + page open
 *        html_page_footer/0          — emit page close
 *        html_writeln/1              — emit text as <p> paragraph or raw HTML
 *        html_write/1                — emit text as <span> or raw HTML
 *        html_safe_writeln/1         — HTML-escape text and emit as <p>
 *        html_safe_write/1           — HTML-escape text and emit inline
 *        looks_like_html/1           — detect HTML fragments
 *        html_escape/2               — escape HTML special characters
 *
 *   3. **Stage 11** — web_support loader:
 *        emit_web_support_loader/1   — emit a single :- use_module(web_support)
 *                                      directive into a generated file so that
 *                                      helpers are loaded from web_support.pl
 *                                      instead of being inlined.
 *
 * HTML fragment detection
 * -----------------------
 * An atom is considered an HTML fragment when it contains both '<' and '>'.
 * When a writeln/write argument is a ground atom that looks like HTML, the
 * converter passes it through as-is rather than wrapping it in <p>/<span>.
 * For runtime variables (not known at conversion time) the runtime helpers
 * html_writeln/1 and html_write/1 perform the same detection at run time.
 *
 * Usage (from the converter)
 * --------------------------
 *   :- use_module('src/html_output').
 *   ?- norm_output_to_html_term(norm_output(writeln('Hi')), T).
 *   T = p('Hi').
 *   ?- norm_output_to_html_term(norm_output(writeln('<b>Hi</b>')), T).
 *   T = \['<b>Hi</b>'].
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

:- use_module(library(lists)).
:- use_module(state_serialiser).

% ==========================================================================
% HTML fragment detection
% ==========================================================================

%% looks_like_html(+Text:atom) is semidet.
%
%  True when Text is an atom that appears to contain HTML markup, i.e. it
%  contains at least one '<' and at least one '>' character.
%
%  This heuristic correctly identifies atoms such as '<p>Hello</p>',
%  '<br/>', and '<b>bold</b>word' as HTML while leaving plain strings like
%  'Enter your name:' or '42' classified as plain text.
looks_like_html(Text) :-
    atom(Text),
    sub_atom(Text, _, _, _, '<'),
    sub_atom(Text, _, _, _, '>').

% ==========================================================================
% HTML escaping
% ==========================================================================

%% html_escape(+In, -Out) is det.
%
%  Replace HTML special characters in In with their entity equivalents:
%    &  →  &amp;   (must be first to avoid double-escaping)
%    <  →  &lt;
%    >  →  &gt;
%    "  →  &quot;
%
%  In may be an atom or a string; Out is an atom.
html_escape(In, Out) :-
    ( atom(In) -> A = In ; atom_string(A, In) ),
    % Replace & first to avoid double-escaping the entities added below.
    atomic_list_concat(Parts0, '&', A),
    atomic_list_concat(Parts0, '&amp;', S1),
    atomic_list_concat(Parts1, '<', S1),
    atomic_list_concat(Parts1, '&lt;', S2),
    atomic_list_concat(Parts2, '>', S2),
    atomic_list_concat(Parts2, '&gt;', S3),
    atomic_list_concat(Parts3, '"', S3),
    atomic_list_concat(Parts3, '&quot;', Out).

% ==========================================================================
% Converter-side: norm_output → HTML term (for reply_html_page/2 form pages)
% ==========================================================================

%% norm_output_to_html_term(+NormOutput, -HtmlTerm) is det.
%
%  Convert a norm_output/1 goal to an HTML term for use as content inside
%  reply_html_page/2.
%
%  When the argument is a ground atom that looks like HTML (detected by
%  looks_like_html/1), the content is passed through as raw HTML using
%  html_write's \[Atom] raw-token escape, so the markup is not re-escaped.
%  format/1,2 goals become \html_format(Fmt, Args), a DCG helper emitted
%  into every generated program (html_write calls \G as a DCG body, so
%  \format(Fmt, Args) would call the non-existent format/4).  Otherwise the standard semantic elements (p, span, br) are
%  used, which html_write will escape the content of appropriately.
norm_output_to_html_term(norm_output(writeln(X)), HtmlTerm) :- !,
    ( atom(X), looks_like_html(X) ->
        HtmlTerm = \[X]                    % HTML fragment — pass through raw
    ;   HtmlTerm = p(X)                     % plain text or variable
    ).
norm_output_to_html_term(norm_output(write(X)), HtmlTerm) :- !,
    ( atom(X), looks_like_html(X) ->
        HtmlTerm = \[X]                    % HTML fragment — pass through raw
    ;   HtmlTerm = span(X)                  % plain text or variable
    ).
norm_output_to_html_term(norm_output(nl),   br([])) :- !.
norm_output_to_html_term(norm_output(print(X)), HtmlTerm) :- !,
    ( atom(X), looks_like_html(X) ->
        HtmlTerm = \[X]
    ;   HtmlTerm = p(X)
    ).
norm_output_to_html_term(norm_output(format(Fmt, Args)),
                         \html_format(Fmt, Args)) :- !.
norm_output_to_html_term(norm_output(format(Fmt)), \html_format(Fmt, [])) :- !.
norm_output_to_html_term(_, p('')).

% ==========================================================================
% Converter-side: norm_output → Prolog call (for raw-format result pages)
% ==========================================================================

%% norm_output_to_result_call(+NormGoal, -Call) is det.
%
%  Convert a normalised goal to a Prolog call suitable for inclusion in a
%  result-page handler body where output is written via format/2.
%
%  For output goals:
%    • If the argument is a ground atom that looks like HTML, emit it raw
%      with format('~w~n', [X]) so that the markup is preserved.
%    • Otherwise emit via the runtime helper html_writeln/1 or html_write/1,
%      which perform the same HTML-fragment check at run time and fall back
%      to wrapping the value in <p>/<span>.
%
%  For compute goals (norm_goal/1), the raw Prolog call is returned unchanged.
norm_output_to_result_call(norm_output(writeln(X)), Call) :- !,
    ( atom(X), looks_like_html(X) ->
        Call = format('~w~n', [X])      % known HTML atom — pass through
    ;   Call = html_writeln(X)          % plain text atom or variable
    ).
norm_output_to_result_call(norm_output(write(X)), Call) :- !,
    ( atom(X), looks_like_html(X) ->
        Call = format('~w', [X])        % known HTML atom — pass through
    ;   Call = html_write(X)            % plain text atom or variable
    ).
norm_output_to_result_call(norm_output(nl),    format('<br/>~n'))  :- !.
norm_output_to_result_call(norm_output(format(Fmt, Args)), format(Fmt, Args)) :- !.
norm_output_to_result_call(norm_output(format(Fmt)), format(Fmt)) :- !.
norm_output_to_result_call(norm_output(print(X)), Call) :- !,
    ( atom(X), looks_like_html(X) ->
        Call = format('~w~n', [X])
    ;   Call = html_writeln(X)
    ).
norm_output_to_result_call(norm_goal(G), G) :- !.
norm_output_to_result_call(_, format('<!-- goal -->~n')).

% ==========================================================================
% Converter-side: emit runtime helper definitions into a generated file
% ==========================================================================

%% emit_html_helpers(+Out:stream) is det.
%
%  Write Prolog source definitions for all runtime helper predicates into the
%  open output stream Out.  These definitions are embedded in every generated
%  web program so that the program is self-contained and does not depend on
%  a separate html_output module being available at the deployment site.
%
%  Predicates emitted:
%    looks_like_html/1, html_escape/2, html_writeln/1, html_write/1,
%    html_safe_writeln/1, html_safe_write/1, html_page_header/1,
%    html_page_footer/0, html_format//2.
emit_html_helpers(Out) :-
    nl(Out),
    format(Out, "%% --------------------------------------------------~n", []),
    format(Out, "%% HTML output helpers (Stage 6)~n", []),
    format(Out, "%% --------------------------------------------------~n~n", []),
    emit_looks_like_html(Out),
    emit_html_escape(Out),
    emit_html_writeln(Out),
    emit_html_write(Out),
    emit_html_safe_writeln(Out),
    emit_html_safe_write(Out),
    emit_html_page_header(Out),
    emit_html_page_footer(Out),
    emit_html_format(Out),
    emit_state_serialiser_helpers(Out).

%  html_format//2: format/2 output as raw HTML inside reply_html_page/2.
emit_html_format(Out) :-
    format(Out, "html_format(Fmt, Args) -->~n", []),
    format(Out, "    { format(atom(A), Fmt, Args) },~n", []),
    format(Out, "    html(\\[A]).~n~n", []).

emit_looks_like_html(Out) :-
    format(Out, "looks_like_html(X) :-~n", []),
    format(Out, "    atom(X),~n", []),
    format(Out, "    sub_atom(X, _, _, _, '<'),~n", []),
    format(Out, "    sub_atom(X, _, _, _, '>').~n~n", []).

emit_html_escape(Out) :-
    format(Out, "html_escape(In, Out) :-~n", []),
    format(Out, "    ( atom(In) -> A = In ; atom_string(A, In) ),~n", []),
    format(Out, "    atomic_list_concat(P0, '&', A),~n", []),
    format(Out, "    atomic_list_concat(P0, '&amp;', S1),~n", []),
    format(Out, "    atomic_list_concat(P1, '<', S1),~n", []),
    format(Out, "    atomic_list_concat(P1, '&lt;', S2),~n", []),
    format(Out, "    atomic_list_concat(P2, '>', S2),~n", []),
    format(Out, "    atomic_list_concat(P2, '&gt;', S3),~n", []),
    format(Out, "    atomic_list_concat(P3, '\"', S3),~n", []),
    format(Out, "    atomic_list_concat(P3, '&quot;', Out).~n~n", []).

emit_html_writeln(Out) :-
    format(Out, "html_writeln(Text) :-~n", []),
    format(Out, "    ( looks_like_html(Text) ->~n", []),
    format(Out, "        format('~~w~~n', [Text])~n", []),
    format(Out, "    ;   format('<p>~~w</p>~~n', [Text])~n", []),
    format(Out, "    ).~n~n", []).

emit_html_write(Out) :-
    format(Out, "html_write(Text) :-~n", []),
    format(Out, "    ( looks_like_html(Text) ->~n", []),
    format(Out, "        format('~~w', [Text])~n", []),
    format(Out, "    ;   format('<span>~~w</span>', [Text])~n", []),
    format(Out, "    ).~n~n", []).

emit_html_safe_writeln(Out) :-
    format(Out, "html_safe_writeln(Text) :-~n", []),
    format(Out, "    html_escape(Text, Escaped),~n", []),
    format(Out, "    format('<p>~~w</p>~~n', [Escaped]).~n~n", []).

emit_html_safe_write(Out) :-
    format(Out, "html_safe_write(Text) :-~n", []),
    format(Out, "    html_escape(Text, Escaped),~n", []),
    format(Out, "    format('~~w', [Escaped]).~n~n", []).

emit_html_page_header(Out) :-
    format(Out, "html_page_header(Title) :-~n", []),
    format(Out, "    format('Content-type: text/html\\n\\n'),~n", []),
    format(Out, "    format('<html>\\n<head><title>~~w</title></head>\\n<body>\\n', [Title]).~n~n", []).

emit_html_page_footer(Out) :-
    format(Out, "html_page_footer :-~n", []),
    format(Out, "    format('</body>\\n</html>\\n').~n~n", []).

% ==========================================================================
% Converter-side: emit a use_module(web_support) loader (Stage 11)
% ==========================================================================

%% emit_web_support_loader(+Out:stream) is det.
%
%  Write a single :- use_module(web_support). directive into the open output
%  stream Out.
%
%  Use this instead of emit_html_helpers/1 when the generated program is
%  deployed alongside web_support.pl and does not need to be fully
%  self-contained.  The web_support module provides all the same runtime
%  helpers (html_page_header/1, html_writeln/1, html_escape/2, etc.) plus
%  additional form-output and request-extraction predicates.
%
%  Generated output:
%    :- use_module(web_support).
emit_web_support_loader(Out) :-
    nl(Out),
    format(Out, "%% --------------------------------------------------~n", []),
    format(Out, "%% Runtime helpers loaded from web_support.pl (Stage 11)~n", []),
    format(Out, "%% --------------------------------------------------~n~n", []),
    format(Out, ":- use_module(web_support).~n~n", []).

% ==========================================================================
% Runtime helpers — page wrapper
% ==========================================================================

%% html_page_header(+Title:atom) is det.
%
%  Write a complete HTTP Content-type header followed by an HTML page opening
%  with the given Title in the <title> element.
%
%  Output written to current_output:
%    Content-type: text/html\n\n
%    <html>\n<head><title>Title</title></head>\n<body>\n
html_page_header(Title) :-
    format('Content-type: text/html\n\n'),
    format('<html>\n<head><title>~w</title></head>\n<body>\n', [Title]).

%% html_page_footer is det.
%
%  Write the closing HTML tags for a page.
%
%  Output written to current_output:
%    </body>\n</html>\n
html_page_footer :-
    format('</body>\n</html>\n').

% ==========================================================================
% Runtime helpers — line / inline output
% ==========================================================================

%% html_writeln(+Text) is det.
%
%  Write Text to current_output as an HTML paragraph, or pass it through
%  unchanged when Text is an atom that looks like HTML markup.
%
%  Plain text (non-HTML atom or runtime variable):
%    format('<p>~w</p>~n', [Text])
%
%  HTML fragment (atom detected by looks_like_html/1):
%    format('~w~n', [Text])
html_writeln(Text) :-
    ( looks_like_html(Text) ->
        format('~w~n', [Text])
    ;   format('<p>~w</p>~n', [Text])
    ).

%% html_write(+Text) is det.
%
%  Write Text to current_output as an inline HTML span, or pass it through
%  unchanged when Text is an atom that looks like HTML markup.
%
%  Plain text:  format('<span>~w</span>', [Text])
%  HTML fragment: format('~w', [Text])
html_write(Text) :-
    ( looks_like_html(Text) ->
        format('~w', [Text])
    ;   format('<span>~w</span>', [Text])
    ).

% ==========================================================================
% Runtime helpers — safe (escaped) output
% ==========================================================================

%% html_safe_writeln(+Text) is det.
%
%  HTML-escape Text (replacing &, <, >, " with their entity equivalents)
%  and write the result as a <p> paragraph.
html_safe_writeln(Text) :-
    html_escape(Text, Escaped),
    format('<p>~w</p>~n', [Escaped]).

%% html_safe_write(+Text) is det.
%
%  HTML-escape Text and write the result inline (no wrapper element).
html_safe_write(Text) :-
    html_escape(Text, Escaped),
    format('~w', [Escaped]).
