%% tests/test_html_output.pl
%%
%% Unit tests for the Stage 6 HTML output conversion module
%% (src/html_output.pl).
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_html_output.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_html_output].
%%   ?- run_tests.

:- use_module('../src/html_output').
:- use_module(library(plunit)).

% ==========================================================================
% Tests: looks_like_html/1
% ==========================================================================

:- begin_tests(looks_like_html).

test(simple_tag) :-
    looks_like_html('<p>Hello</p>').

test(br_tag) :-
    looks_like_html('<br/>').

test(heading) :-
    looks_like_html('<h1>Title</h1>').

test(mixed_content) :-
    looks_like_html('Hello <b>World</b>!').

test(plain_text_fails, [fail]) :-
    looks_like_html('Enter your name:').

test(number_fails, [fail]) :-
    looks_like_html('42').

test(empty_atom_fails, [fail]) :-
    looks_like_html('').

test(only_lt_fails, [fail]) :-
    looks_like_html('a < b').

test(only_gt_fails, [fail]) :-
    looks_like_html('a > b').

test(variable_fails, [fail]) :-
    looks_like_html(_X).

:- end_tests(looks_like_html).

% ==========================================================================
% Tests: html_escape/2
% ==========================================================================

:- begin_tests(html_escape).

test(ampersand) :-
    html_escape('a&b', 'a&amp;b').

test(less_than) :-
    html_escape('a<b', 'a&lt;b').

test(greater_than) :-
    html_escape('a>b', 'a&gt;b').

test(double_quote) :-
    html_escape('say "hi"', 'say &quot;hi&quot;').

test(multiple_special_chars) :-
    html_escape('<b>a & b</b>', '&lt;b&gt;a &amp; b&lt;/b&gt;').

test(plain_text_unchanged) :-
    html_escape('Hello World', 'Hello World').

test(empty_atom) :-
    html_escape('', '').

:- end_tests(html_escape).

% ==========================================================================
% Tests: norm_output_to_html_term/2 — plain text and variables
% ==========================================================================

:- begin_tests(norm_output_to_html_term_plain).

test(writeln_plain_text_becomes_p) :-
    norm_output_to_html_term(norm_output(writeln('Enter name:')), p('Enter name:')).

test(write_plain_text_becomes_span) :-
    norm_output_to_html_term(norm_output(write('ok')), span('ok')).

test(writeln_variable_becomes_p) :-
    norm_output_to_html_term(norm_output(writeln(_X)), p(_Y)).

test(write_variable_becomes_span) :-
    norm_output_to_html_term(norm_output(write(_X)), span(_Y)).

test(nl_becomes_br) :-
    norm_output_to_html_term(norm_output(nl), br([])).

test(print_becomes_p) :-
    norm_output_to_html_term(norm_output(print(hello)), p(hello)).

test(format2_becomes_escape) :-
    norm_output_to_html_term(norm_output(format("~w~n", [x])),
                             \(format("~w~n", [x]))).

test(format1_becomes_escape) :-
    norm_output_to_html_term(norm_output(format("hello")),
                             \(format("hello"))).

test(unknown_becomes_empty_p) :-
    norm_output_to_html_term(norm_output(foo(bar)), p('')).

:- end_tests(norm_output_to_html_term_plain).

% ==========================================================================
% Tests: norm_output_to_html_term/2 — HTML fragment pass-through
% ==========================================================================

:- begin_tests(norm_output_to_html_term_html).

test(writeln_html_fragment_passthrough) :-
    norm_output_to_html_term(norm_output(writeln('<h1>Hi</h1>')), HT),
    HT = \(format('~w~n', ['<h1>Hi</h1>'])).

test(write_html_fragment_passthrough) :-
    norm_output_to_html_term(norm_output(write('<b>bold</b>')), HT),
    HT = \(format('~w', ['<b>bold</b>'])).

test(print_html_fragment_passthrough) :-
    norm_output_to_html_term(norm_output(print('<em>em</em>')), HT),
    HT = \(format('~w~n', ['<em>em</em>'])).

test(mixed_content_passthrough) :-
    norm_output_to_html_term(norm_output(writeln('Hello <b>World</b>!')), HT),
    HT = \(format('~w~n', ['Hello <b>World</b>!'])).

:- end_tests(norm_output_to_html_term_html).

% ==========================================================================
% Tests: norm_output_to_result_call/2 — plain text and variables
% ==========================================================================

:- begin_tests(norm_output_to_result_call_plain).

test(writeln_plain_text_uses_html_writeln) :-
    norm_output_to_result_call(norm_output(writeln('ok')), html_writeln('ok')).

test(write_plain_text_uses_html_write) :-
    norm_output_to_result_call(norm_output(write('hi')), html_write('hi')).

test(writeln_variable_uses_html_writeln) :-
    norm_output_to_result_call(norm_output(writeln(_X)), html_writeln(_Y)).

test(write_variable_uses_html_write) :-
    norm_output_to_result_call(norm_output(write(_X)), html_write(_Y)).

test(nl_becomes_br_format) :-
    norm_output_to_result_call(norm_output(nl), format('<br/>~n')).

test(format2_passes_through) :-
    norm_output_to_result_call(norm_output(format("~w~n", [x])),
                               format("~w~n", [x])).

test(format1_passes_through) :-
    norm_output_to_result_call(norm_output(format("hello")), format("hello")).

test(print_plain_text_uses_html_writeln) :-
    norm_output_to_result_call(norm_output(print(hello)), html_writeln(hello)).

test(norm_goal_passes_through) :-
    norm_output_to_result_call(norm_goal(assert(foo)), assert(foo)).

:- end_tests(norm_output_to_result_call_plain).

% ==========================================================================
% Tests: norm_output_to_result_call/2 — HTML fragment pass-through
% ==========================================================================

:- begin_tests(norm_output_to_result_call_html).

test(writeln_html_fragment_raw_format) :-
    norm_output_to_result_call(norm_output(writeln('<h1>Title</h1>')),
                               format('~w~n', ['<h1>Title</h1>'])).

test(write_html_fragment_raw_format) :-
    norm_output_to_result_call(norm_output(write('<br/>')),
                               format('~w', ['<br/>'])).

test(print_html_fragment_raw_format) :-
    norm_output_to_result_call(norm_output(print('<em>e</em>')),
                               format('~w~n', ['<em>e</em>'])).

:- end_tests(norm_output_to_result_call_html).

% ==========================================================================
% Tests: emit_html_helpers/1 — structural content check
% ==========================================================================

:- begin_tests(emit_html_helpers).

test(emits_looks_like_html_definition) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'looks_like_html').

test(emits_html_escape_definition) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'html_escape').

test(emits_html_writeln_definition) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'html_writeln').

test(emits_html_write_definition) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'html_write').

test(emits_html_safe_writeln_definition) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'html_safe_writeln').

test(emits_html_safe_write_definition) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'html_safe_write').

test(emits_html_page_header_definition) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'html_page_header').

test(emits_html_page_footer_definition) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'html_page_footer').

test(emits_content_type_in_header_def) :-
    with_output_to(atom(Out), html_output:emit_html_helpers(current_output)),
    sub_atom(Out, _, _, _, 'Content-type').

:- end_tests(emit_html_helpers).

% ==========================================================================
% Tests: runtime helpers — html_page_header/1 and html_page_footer/0
% ==========================================================================

:- begin_tests(html_page_header).

test(emits_content_type) :-
    with_output_to(atom(Out), html_page_header('My Page')),
    sub_atom(Out, _, _, _, 'Content-type: text/html').

test(emits_html_open) :-
    with_output_to(atom(Out), html_page_header('My Page')),
    sub_atom(Out, _, _, _, '<html>').

test(emits_head_with_title) :-
    with_output_to(atom(Out), html_page_header('My Page')),
    sub_atom(Out, _, _, _, '<title>My Page</title>').

test(emits_body_open) :-
    with_output_to(atom(Out), html_page_header('My Page')),
    sub_atom(Out, _, _, _, '<body>').

:- end_tests(html_page_header).

:- begin_tests(html_page_footer).

test(emits_body_close) :-
    with_output_to(atom(Out), html_page_footer),
    sub_atom(Out, _, _, _, '</body>').

test(emits_html_close) :-
    with_output_to(atom(Out), html_page_footer),
    sub_atom(Out, _, _, _, '</html>').

:- end_tests(html_page_footer).

% ==========================================================================
% Tests: runtime helpers — html_writeln/1 and html_write/1
% ==========================================================================

:- begin_tests(html_writeln).

test(plain_text_wrapped_in_p) :-
    with_output_to(atom(Out), html_writeln('Hello World')),
    sub_atom(Out, _, _, _, '<p>Hello World</p>').

test(html_fragment_passed_through) :-
    with_output_to(atom(Out), html_writeln('<h1>Title</h1>')),
    sub_atom(Out, _, _, _, '<h1>Title</h1>'),
    \+ sub_atom(Out, _, _, _, '<p>').

:- end_tests(html_writeln).

:- begin_tests(html_write).

test(plain_text_wrapped_in_span) :-
    with_output_to(atom(Out), html_write('Hello')),
    sub_atom(Out, _, _, _, '<span>Hello</span>').

test(html_fragment_passed_through) :-
    with_output_to(atom(Out), html_write('<b>bold</b>')),
    sub_atom(Out, _, _, _, '<b>bold</b>'),
    \+ sub_atom(Out, _, _, _, '<span>').

:- end_tests(html_write).

% ==========================================================================
% Tests: runtime helpers — html_safe_writeln/1 and html_safe_write/1
% ==========================================================================

:- begin_tests(html_safe_writeln).

test(escapes_lt_gt) :-
    with_output_to(atom(Out), html_safe_writeln('<script>')),
    sub_atom(Out, _, _, _, '&lt;script&gt;'),
    \+ sub_atom(Out, _, _, _, '<script>').

test(wrapped_in_p) :-
    with_output_to(atom(Out), html_safe_writeln('Hello')),
    sub_atom(Out, _, _, _, '<p>Hello</p>').

:- end_tests(html_safe_writeln).

:- begin_tests(html_safe_write).

test(escapes_ampersand) :-
    with_output_to(atom(Out), html_safe_write('a&b')),
    sub_atom(Out, _, _, _, '&amp;').

test(no_p_wrapper) :-
    with_output_to(atom(Out), html_safe_write('hi')),
    sub_atom(Out, _, _, _, 'hi'),
    \+ sub_atom(Out, _, _, _, '<p>').

:- end_tests(html_safe_write).
