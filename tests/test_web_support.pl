%% tests/test_web_support.pl
%%
%% Unit tests for the Stage 11 web support library (src/web_support.pl).
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_web_support.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_web_support].
%%   ?- run_tests.

:- use_module('../src/web_support').
:- use_module(library(plunit)).

% ==========================================================================
% Tests: looks_like_html/1
% ==========================================================================

:- begin_tests(ws_looks_like_html).

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

:- end_tests(ws_looks_like_html).

% ==========================================================================
% Tests: html_escape/2
% ==========================================================================

:- begin_tests(ws_html_escape).

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

test(string_input) :-
    html_escape("a<b", Out),
    Out == 'a&lt;b'.

:- end_tests(ws_html_escape).

% ==========================================================================
% Tests: html_page_header/1
% ==========================================================================

:- begin_tests(ws_html_page_header).

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

:- end_tests(ws_html_page_header).

% ==========================================================================
% Tests: html_page_footer/0
% ==========================================================================

:- begin_tests(ws_html_page_footer).

test(emits_body_close) :-
    with_output_to(atom(Out), html_page_footer),
    sub_atom(Out, _, _, _, '</body>').

test(emits_html_close) :-
    with_output_to(atom(Out), html_page_footer),
    sub_atom(Out, _, _, _, '</html>').

:- end_tests(ws_html_page_footer).

% ==========================================================================
% Tests: html_writeln/1
% ==========================================================================

:- begin_tests(ws_html_writeln).

test(plain_text_wrapped_in_p) :-
    with_output_to(atom(Out), html_writeln('Hello World')),
    sub_atom(Out, _, _, _, '<p>Hello World</p>').

test(html_fragment_passed_through) :-
    with_output_to(atom(Out), html_writeln('<h1>Title</h1>')),
    sub_atom(Out, _, _, _, '<h1>Title</h1>'),
    \+ sub_atom(Out, _, _, _, '<p>').

test(integer_wrapped_in_p) :-
    with_output_to(atom(Out), html_writeln(42)),
    sub_atom(Out, _, _, _, '<p>42</p>').

:- end_tests(ws_html_writeln).

% ==========================================================================
% Tests: html_write/1
% ==========================================================================

:- begin_tests(ws_html_write).

test(plain_text_wrapped_in_span) :-
    with_output_to(atom(Out), html_write('Hello')),
    sub_atom(Out, _, _, _, '<span>Hello</span>').

test(html_fragment_passed_through) :-
    with_output_to(atom(Out), html_write('<b>bold</b>')),
    sub_atom(Out, _, _, _, '<b>bold</b>'),
    \+ sub_atom(Out, _, _, _, '<span>').

:- end_tests(ws_html_write).

% ==========================================================================
% Tests: html_br/0
% ==========================================================================

:- begin_tests(ws_html_br).

test(emits_br_tag) :-
    with_output_to(atom(Out), html_br),
    sub_atom(Out, _, _, _, '<br/>').

:- end_tests(ws_html_br).

% ==========================================================================
% Tests: html_safe_writeln/1
% ==========================================================================

:- begin_tests(ws_html_safe_writeln).

test(escapes_lt_gt) :-
    with_output_to(atom(Out), html_safe_writeln('<script>')),
    sub_atom(Out, _, _, _, '&lt;script&gt;'),
    \+ sub_atom(Out, _, _, _, '<script>').

test(wrapped_in_p) :-
    with_output_to(atom(Out), html_safe_writeln('Hello')),
    sub_atom(Out, _, _, _, '<p>Hello</p>').

:- end_tests(ws_html_safe_writeln).

% ==========================================================================
% Tests: html_safe_write/1
% ==========================================================================

:- begin_tests(ws_html_safe_write).

test(escapes_ampersand) :-
    with_output_to(atom(Out), html_safe_write('a&b')),
    sub_atom(Out, _, _, _, '&amp;').

test(no_p_wrapper) :-
    with_output_to(atom(Out), html_safe_write('hi')),
    sub_atom(Out, _, _, _, 'hi'),
    \+ sub_atom(Out, _, _, _, '<p>').

:- end_tests(ws_html_safe_write).

% ==========================================================================
% Tests: state_serialise/2
% ==========================================================================

:- begin_tests(ws_state_serialise).

test(atom_serialises) :-
    state_serialise(hello, A),
    A == hello.

test(integer_serialises) :-
    state_serialise(42, A),
    A == '42'.

test(list_serialises) :-
    state_serialise([1,2,3], A),
    A == '[1,2,3]'.

test(compound_serialises) :-
    state_serialise(foo(bar), A),
    atom(A).

:- end_tests(ws_state_serialise).

% ==========================================================================
% Tests: state_deserialise/2
% ==========================================================================

:- begin_tests(ws_state_deserialise).

test(atom_roundtrip) :-
    state_serialise(hello, A),
    state_deserialise(A, T),
    T == hello.

test(integer_roundtrip) :-
    state_serialise(42, A),
    state_deserialise(A, T),
    T == 42.

test(list_roundtrip) :-
    state_serialise([a,b,c], A),
    state_deserialise(A, T),
    T == [a,b,c].

test(plain_string_fallback) :-
    state_deserialise('Hello World', T),
    T == 'Hello World'.

:- end_tests(ws_state_deserialise).

% ==========================================================================
% Tests: raw form output helpers
% ==========================================================================

:- begin_tests(ws_form_open).

test(emits_form_tag) :-
    with_output_to(atom(Out), ws_form_open('/step_1', post)),
    sub_atom(Out, _, _, _, '<form').

test(emits_action) :-
    with_output_to(atom(Out), ws_form_open('/step_1', post)),
    sub_atom(Out, _, _, _, '/step_1').

test(emits_method) :-
    with_output_to(atom(Out), ws_form_open('/step_1', post)),
    sub_atom(Out, _, _, _, 'post').

:- end_tests(ws_form_open).

:- begin_tests(ws_form_close).

test(emits_closing_form) :-
    with_output_to(atom(Out), ws_form_close),
    sub_atom(Out, _, _, _, '</form>').

:- end_tests(ws_form_close).

:- begin_tests(ws_text_input).

test(emits_text_input) :-
    with_output_to(atom(Out), ws_text_input('Name')),
    sub_atom(Out, _, _, _, 'type="text"').

test(emits_name_attribute) :-
    with_output_to(atom(Out), ws_text_input('Name')),
    sub_atom(Out, _, _, _, 'name="Name"').

test(emits_autofocus) :-
    with_output_to(atom(Out), ws_text_input('Name')),
    sub_atom(Out, _, _, _, 'autofocus').

:- end_tests(ws_text_input).

:- begin_tests(ws_password_input).

test(emits_password_type) :-
    with_output_to(atom(Out), ws_password_input('Pass')),
    sub_atom(Out, _, _, _, 'type="password"').

test(emits_name_attribute) :-
    with_output_to(atom(Out), ws_password_input('Pass')),
    sub_atom(Out, _, _, _, 'name="Pass"').

:- end_tests(ws_password_input).

:- begin_tests(ws_textarea_input).

test(emits_textarea_tag) :-
    with_output_to(atom(Out), ws_textarea_input('Message')),
    sub_atom(Out, _, _, _, '<textarea').

test(emits_name_attribute) :-
    with_output_to(atom(Out), ws_textarea_input('Message')),
    sub_atom(Out, _, _, _, 'name="Message"').

:- end_tests(ws_textarea_input).

:- begin_tests(ws_hidden_input).

test(emits_hidden_type) :-
    with_output_to(atom(Out), ws_hidden_input('Token', secret)),
    sub_atom(Out, _, _, _, 'type="hidden"').

test(emits_name_attribute) :-
    with_output_to(atom(Out), ws_hidden_input('Token', secret)),
    sub_atom(Out, _, _, _, 'name="Token"').

test(emits_value_attribute) :-
    with_output_to(atom(Out), ws_hidden_input('Token', secret)),
    sub_atom(Out, _, _, _, 'value="secret"').

test(escapes_value_html) :-
    with_output_to(atom(Out), ws_hidden_input('X', '<b>')),
    sub_atom(Out, _, _, _, '&lt;b&gt;'),
    \+ sub_atom(Out, _, _, _, '<b>').

:- end_tests(ws_hidden_input).

:- begin_tests(ws_submit).

test(emits_submit_type) :-
    with_output_to(atom(Out), ws_submit('Next')),
    sub_atom(Out, _, _, _, 'type="submit"').

test(emits_label_value) :-
    with_output_to(atom(Out), ws_submit('Next')),
    sub_atom(Out, _, _, _, 'value="Next"').

:- end_tests(ws_submit).

% ==========================================================================
% Tests: emit_web_support_loader/1 (html_output module)
% ==========================================================================

:- use_module('../src/html_output').

:- begin_tests(emit_web_support_loader).

test(emits_use_module_directive) :-
    with_output_to(atom(Out),
                   html_output:emit_web_support_loader(current_output)),
    sub_atom(Out, _, _, _, ':- use_module(web_support).').

test(emits_stage_comment) :-
    with_output_to(atom(Out),
                   html_output:emit_web_support_loader(current_output)),
    sub_atom(Out, _, _, _, 'Stage 11').

:- end_tests(emit_web_support_loader).
