%% tests/test_form_generator.pl
%%
%% Unit tests for the Stage 7 form generator (src/form_generator.pl).
%%
%% Tests cover:
%%   - select_input_type/4  — input-type selection logic
%%   - build_hidden_inputs/3 — hidden state carrier
%%   - build_input_field/3   — per-type HTML input field builder
%%   - generate_form/7       — complete form assembler
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_form_generator.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_form_generator].
%%   ?- run_tests.

:- use_module('../src/form_generator').
:- use_module(library(plunit)).
:- use_module(library(lists)).

% ==========================================================================
% Tests: select_input_type/4
% ==========================================================================

:- begin_tests(select_input_type).

% read_password always yields password, regardless of var name or prompts.

test(read_password_gives_password) :-
    select_input_type(read_password, 'Any', [], password).

test(read_password_ignores_varname) :-
    select_input_type(read_password, 'Name', [], password).

test(read_password_ignores_prompts) :-
    select_input_type(read_password, 'Foo',
                      [norm_output(writeln('Enter name:'))],
                      password).

% read_string defaults to text when no semantic hints are present.

test(read_string_default_is_text) :-
    select_input_type(read_string, 'Name', [], text).

test(read_string_neutral_varname_is_text) :-
    select_input_type(read_string, 'Choice', [], text).

test(read_string_neutral_prompts_is_text) :-
    select_input_type(read_string, 'Input',
                      [norm_output(writeln('Enter value:'))],
                      text).

% read_string with a password-like variable name yields password.

test(password_varname_exact) :-
    select_input_type(read_string, 'Password', [], password).

test(password_varname_mixed_case) :-
    select_input_type(read_string, 'UserPassword', [], password).

test(passwd_varname) :-
    select_input_type(read_string, 'Passwd', [], password).

test(secret_varname) :-
    select_input_type(read_string, 'Secret', [], password).

test(pin_varname) :-
    select_input_type(read_string, 'Pin', [], password).

% read_string with a textarea-hint variable name yields textarea.

test(description_varname_gives_textarea) :-
    select_input_type(read_string, 'Description', [], textarea).

test(message_varname_gives_textarea) :-
    select_input_type(read_string, 'Message', [], textarea).

test(comment_varname_gives_textarea) :-
    select_input_type(read_string, 'Comment', [], textarea).

test(note_varname_gives_textarea) :-
    select_input_type(read_string, 'Note', [], textarea).

test(bio_varname_gives_textarea) :-
    select_input_type(read_string, 'Bio', [], textarea).

test(about_varname_gives_textarea) :-
    select_input_type(read_string, 'About', [], textarea).

test(body_varname_gives_textarea) :-
    select_input_type(read_string, 'Body', [], textarea).

test(content_varname_gives_textarea) :-
    select_input_type(read_string, 'Content', [], textarea).

test(feedback_varname_gives_textarea) :-
    select_input_type(read_string, 'Feedback', [], textarea).

% read_string with a textarea-hint prompt yields textarea.

test(describe_prompt_gives_textarea) :-
    select_input_type(read_string, 'Input',
                      [norm_output(writeln('Please describe your issue:'))],
                      textarea).

test(your_message_prompt_gives_textarea) :-
    select_input_type(read_string, 'Input',
                      [norm_output(writeln('Enter your message here:'))],
                      textarea).

test(your_comment_prompt_gives_textarea) :-
    select_input_type(read_string, 'Input',
                      [norm_output(writeln('Enter your comment:'))],
                      textarea).

test(your_note_prompt_gives_textarea) :-
    select_input_type(read_string, 'Input',
                      [norm_output(writeln('Enter your note:'))],
                      textarea).

test(write_a_prompt_gives_textarea) :-
    select_input_type(read_string, 'Input',
                      [norm_output(writeln('Please write a brief summary:'))],
                      textarea).

% Password hint takes priority over textarea hint.

test(password_takes_priority_over_textarea_name) :-
    % A variable called 'PasswordDescription' contains both hints;
    % the password check runs first and wins.
    select_input_type(read_string, 'PasswordDescription', [], password).

:- end_tests(select_input_type).

% ==========================================================================
% Tests: build_hidden_inputs/3
% ==========================================================================

:- begin_tests(build_hidden_inputs).

test(empty_names_gives_empty_list) :-
    build_hidden_inputs([], [], []).

test(single_hidden_input_structure) :-
    V = _,
    VN = ['Name' = V],
    build_hidden_inputs(['Name'], VN, Inputs),
    Inputs = [input([type=hidden, name='Name', value=V])].

test(hidden_input_value_is_the_prolog_variable) :-
    V = _,
    VN = ['X' = V],
    build_hidden_inputs(['X'], VN, [input([type=hidden, name='X', value=Val])]),
    Val == V.

test(multiple_hidden_inputs_count) :-
    V1 = _, V2 = _, V3 = _,
    VN = ['A' = V1, 'B' = V2, 'C' = V3],
    build_hidden_inputs(['A', 'B', 'C'], VN, Inputs),
    length(Inputs, 3).

test(hidden_inputs_preserve_order) :-
    V1 = _, V2 = _,
    VN = ['First' = V1, 'Second' = V2],
    build_hidden_inputs(['First', 'Second'], VN, Inputs),
    Inputs = [input([type=hidden, name='First', value=_]),
              input([type=hidden, name='Second', value=_])].

:- end_tests(build_hidden_inputs).

% ==========================================================================
% Tests: build_input_field/3
% ==========================================================================

:- begin_tests(build_input_field).

test(text_input_is_input_element) :-
    build_input_field(text, 'Name', Field),
    Field = input(_).

test(text_input_has_type_text) :-
    build_input_field(text, 'Name', input(Attrs)),
    member(type=text, Attrs).

test(text_input_has_correct_name) :-
    build_input_field(text, 'Name', input(Attrs)),
    member(name='Name', Attrs).

test(text_input_has_autofocus) :-
    build_input_field(text, 'Name', input(Attrs)),
    member(autofocus=autofocus, Attrs).

test(password_input_has_type_password) :-
    build_input_field(password, 'Pass', input(Attrs)),
    member(type=password, Attrs).

test(password_input_has_correct_name) :-
    build_input_field(password, 'Pass', input(Attrs)),
    member(name='Pass', Attrs).

test(password_input_has_autofocus) :-
    build_input_field(password, 'Pass', input(Attrs)),
    member(autofocus=autofocus, Attrs).

test(textarea_input_is_textarea_element) :-
    build_input_field(textarea, 'Desc', Field),
    Field = textarea(_, _).

test(textarea_input_has_correct_name) :-
    build_input_field(textarea, 'Desc', textarea(Attrs, _)),
    member(name='Desc', Attrs).

test(textarea_input_has_autofocus) :-
    build_input_field(textarea, 'Desc', textarea(Attrs, _)),
    member(autofocus=autofocus, Attrs).

test(textarea_input_has_rows) :-
    build_input_field(textarea, 'Desc', textarea(Attrs, _)),
    member(rows=_, Attrs).

test(textarea_input_has_cols) :-
    build_input_field(textarea, 'Desc', textarea(Attrs, _)),
    member(cols=_, Attrs).

test(unknown_type_falls_back_to_text) :-
    build_input_field(unknown, 'X', input(Attrs)),
    member(type=text, Attrs).

:- end_tests(build_input_field).

% ==========================================================================
% Tests: generate_form/7
% ==========================================================================

:- begin_tests(generate_form).

test(form_has_method_post) :-
    generate_form([], 'X', [], step_1, text, [], Form),
    Form = form([method=post | _], _).

test(form_action_has_slash_prefix) :-
    generate_form([], 'X', [], step_1, text, [], Form),
    Form = form(Attrs, _),
    member(action=Action, Attrs),
    sub_atom(Action, 0, _, _, '/').

test(form_action_targets_next_step) :-
    generate_form([], 'X', [], step_3, text, [], Form),
    Form = form(Attrs, _),
    member(action='/step_3', Attrs).

test(form_children_include_input_field) :-
    generate_form([], 'Name', [], step_1, text, [], form(_, Children)),
    member(input(InputAttrs), Children),
    member(type=text, InputAttrs),
    member(name='Name', InputAttrs).

test(form_children_include_submit_button) :-
    generate_form([], 'Name', [], step_1, text, [], form(_, Children)),
    member(input(SubmitAttrs), Children),
    member(type=submit, SubmitAttrs).

test(form_with_hidden_fields_includes_them) :-
    V = _,
    VN = ['Prev' = V],
    generate_form([], 'New', ['Prev'], step_2, text, VN, form(_, Children)),
    member(input(HAttr), Children),
    member(type=hidden, HAttr),
    member(name='Prev', HAttr).

test(form_with_prompt_includes_prompt_html) :-
    generate_form([norm_output(writeln('Enter name:'))], 'Name', [],
                  step_1, text, [], form(_, Children)),
    member(p('Enter name:'), Children).

test(form_password_type_generates_password_input) :-
    generate_form([], 'Pass', [], step_1, password, [], form(_, Children)),
    member(input(Attrs), Children),
    member(type=password, Attrs).

test(form_textarea_type_generates_textarea) :-
    generate_form([], 'Desc', [], step_1, textarea, [], form(_, Children)),
    member(textarea(_, _), Children).

test(form_child_order_hidden_then_prompts_then_input_then_submit) :-
    V = _,
    VN = ['Prev' = V],
    generate_form([norm_output(writeln('Enter:'))], 'New', ['Prev'],
                  step_2, text, VN, form(_, Children)),
    % The hidden field should come before the input field.
    nth1(HidIdx, Children, input(HAttr)), member(type=hidden, HAttr), !,
    nth1(InIdx,  Children, input(InAttr)), member(type=text,   InAttr), !,
    HidIdx < InIdx.

:- end_tests(generate_form).

% ==========================================================================
% Tests: InputKind threading in continuation_extractor
% ==========================================================================

:- use_module('../src/continuation_extractor').
:- use_module('../src/checkpoint_detector').

:- begin_tests(form_resp_inputkind).

%% Helper — build checkpoints from a body with two read_string goals.
build_two_read_string_checkpoints(CPs, VN) :-
    V1 = _, V2 = _,
    VN = ['Name' = V1, 'Age' = V2],
    Body = norm_conj(
        norm_read_string(user, "\n", "\r", _, V1),
        norm_conj(
            norm_read_string(user, "\n", "\r", _, V2),
            norm_output(format("~w ~w~n", [V1, V2]))
        )
    ),
    detect_checkpoints(Body, VN, CPs).

%% Helper — build checkpoints from a body with a read_password goal.
build_read_password_checkpoint(CPs, VN) :-
    V = _,
    VN = ['Pass' = V],
    Body = norm_read_password('Enter password:', V),
    detect_checkpoints(Body, VN, CPs).

%% Helper — build checkpoints from a body with a read_string where VarName suggests password.
build_password_varname_checkpoint(CPs, VN) :-
    V = _,
    VN = ['Password' = V],
    Body = norm_read_string(user, "\n", "\r", _, V),
    detect_checkpoints(Body, VN, CPs).

%% Helper — build checkpoints from a body with a read_string where VarName suggests textarea.
build_textarea_varname_checkpoint(CPs, VN) :-
    V = _,
    VN = ['Description' = V],
    Body = norm_read_string(user, "\n", "\r", _, V),
    detect_checkpoints(Body, VN, CPs).

test(read_string_gets_text_inputkind) :-
    build_two_read_string_checkpoints(CPs, VN),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, form_resp(_, 'Name', _, _, text)).

test(read_password_gets_password_inputkind) :-
    build_read_password_checkpoint(CPs, VN),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, form_resp(_, 'Pass', _, _, password)).

test(password_varname_gets_password_inputkind) :-
    build_password_varname_checkpoint(CPs, VN),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, form_resp(_, 'Password', _, _, password)).

test(textarea_varname_gets_textarea_inputkind) :-
    build_textarea_varname_checkpoint(CPs, VN),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, form_resp(_, 'Description', _, _, textarea)).

:- end_tests(form_resp_inputkind).
