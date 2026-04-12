%% tests/test_menu_recogniser.pl
%%
%% Unit and integration tests for the Stage 9 menu recogniser module
%% (src/menu_recogniser.pl) and the menu-to-form converter additions
%% in src/form_generator.pl and src/continuation_extractor.pl.
%%
%% Covers:
%%   - extract_menu_choices/4  — parsing an if-then-else chain
%%   - is_menu_checkpoint/4    — full menu detection
%%   - menu_input_kind/2       — widget selection by choice count
%%   - build_menu_input/4      — HTML element generation
%%   - generate_menu_form/8    — complete menu form assembly
%%   - Numbered selection flow — auth_example integration
%%   - Quit (q) behaviour preservation
%%   - Re-display on invalid input (retry detection)
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_menu_recogniser.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_menu_recogniser].
%%   ?- run_tests.

:- use_module('../src/menu_recogniser').
:- use_module('../src/form_generator').
:- use_module('../src/checkpoint_detector').
:- use_module('../src/continuation_extractor').
:- use_module('../src/reader').
:- use_module(library(plunit)).
:- use_module(library(lists)).

:- prolog_load_context(directory, Dir),
   assert(mr_test_dir(Dir)).

% ==========================================================================
% Helpers — build normalised terms for testing
% ==========================================================================

%% build_menu_checkpoint(-CP, -VN, -ChoiceVar) is det.
%
%  Build a menu-style checkpoint like the auth_example 'Choose 1/2/3' screen:
%    writeln('=== Menu ===')
%    writeln('1. Alpha')
%    writeln('2. Beta')
%    writeln('3. Gamma')
%    writeln('Enter choice (1/2/3):')
%    read_string(…, Choice)
%    (Choice = "1" -> … ; Choice = "2" -> … ; Choice = "3" -> … ; invalid)
build_menu_checkpoint(CP, VN, ChoiceVar) :-
    ChoiceVar = _,
    VN = ['Choice' = ChoiceVar],
    Prompts = [ norm_output(writeln('=== Menu ===')),
                norm_output(writeln('1. Alpha')),
                norm_output(writeln('2. Beta')),
                norm_output(writeln('3. Gamma')),
                norm_output(writeln('Enter choice (1/2/3):'))
              ],
    Cont = norm_if_then_else(
               norm_goal(ChoiceVar = "1"),
               norm_output(writeln('You chose Alpha')),
               norm_if_then_else(
                   norm_goal(ChoiceVar = "2"),
                   norm_output(writeln('You chose Beta')),
                   norm_if_then_else(
                       norm_goal(ChoiceVar = "3"),
                       norm_output(writeln('You chose Gamma')),
                       norm_output(writeln('Invalid choice'))
                   )
               )
           ),
    CP = checkpoint(1, read_string, 'Choice', Prompts, Cont, [], sequential).

%% build_non_menu_checkpoint(-CP, -VN) is det.
%
%  A plain read_string checkpoint with no numbered prompts and no
%  if-then-else continuation.  Should NOT be detected as a menu.
build_non_menu_checkpoint(CP, VN) :-
    V = _,
    VN = ['Name' = V],
    Prompts = [norm_output(writeln('Enter your name:'))],
    Cont = norm_output(format("Hello ~w~n", [V])),
    CP = checkpoint(1, read_string, 'Name', Prompts, Cont, [], sequential).

%% build_single_choice_checkpoint(-CP, -VN) is det.
%
%  A checkpoint with a numbered prompt but only one if-then branch.
%  Should be detected as a menu (one choice is enough if there is a
%  numbered prompt).
build_single_choice_checkpoint(CP, VN) :-
    V = _,
    VN = ['Choice' = V],
    Prompts = [norm_output(writeln('1. Yes')),
               norm_output(writeln('Enter choice:'))],
    Cont = norm_if_then_else(
               norm_goal(V = "1"),
               norm_output(writeln('Confirmed')),
               norm_output(writeln('Cancelled'))
           ),
    CP = checkpoint(1, read_string, 'Choice', Prompts, Cont, [], sequential).

%% build_quit_checkpoint(-CP, -VN) is det.
%
%  A checkpoint where one of the choices is 'q' (quit).
build_quit_checkpoint(CP, VN) :-
    V = _,
    VN = ['Choice' = V],
    Prompts = [ norm_output(writeln('1. Start')),
                norm_output(writeln('q. Quit')),
                norm_output(writeln('Enter choice:'))
              ],
    Cont = norm_if_then_else(
               norm_goal(V = "1"),
               norm_output(writeln('Starting...')),
               norm_if_then_else(
                   norm_goal(V = "q"),
                   norm_output(writeln('Goodbye')),
                   norm_output(writeln('Invalid'))
               )
           ),
    CP = checkpoint(1, read_string, 'Choice', Prompts, Cont, [], sequential).

%% build_retry_checkpoint(-CP, -VN) is det.
%
%  A checkpoint whose invalid-input else arm contains a recursive call
%  (representing a re-display loop).
build_retry_checkpoint(CP, VN) :-
    V = _,
    VN = ['Choice' = V],
    Prompts = [ norm_output(writeln('1. Option A')),
                norm_output(writeln('2. Option B')),
                norm_output(writeln('Pick 1 or 2:'))
              ],
    Cont = norm_if_then_else(
               norm_goal(V = "1"),
               norm_output(writeln('Option A')),
               norm_if_then_else(
                   norm_goal(V = "2"),
                   norm_output(writeln('Option B')),
                   norm_conj(
                       norm_output(writeln('Invalid, try again')),
                       norm_goal(loop)     % recursive call → retry
                   )
               )
           ),
    CP = checkpoint(1, read_string, 'Choice', Prompts, Cont, [], loop(loop/0)).

%% build_large_menu_checkpoint(-CP, -VN) is det.
%
%  A checkpoint with 5 choices — should trigger select InputKind.
build_large_menu_checkpoint(CP, VN) :-
    V = _,
    VN = ['Choice' = V],
    Prompts = [ norm_output(writeln('1. A')),
                norm_output(writeln('2. B')),
                norm_output(writeln('3. C')),
                norm_output(writeln('4. D')),
                norm_output(writeln('5. E')),
                norm_output(writeln('Pick:'))
              ],
    Cont = norm_if_then_else(norm_goal(V = "1"), norm_output(writeln(a)),
           norm_if_then_else(norm_goal(V = "2"), norm_output(writeln(b)),
           norm_if_then_else(norm_goal(V = "3"), norm_output(writeln(c)),
           norm_if_then_else(norm_goal(V = "4"), norm_output(writeln(d)),
                             norm_output(writeln(e)))))),
    CP = checkpoint(1, read_string, 'Choice', Prompts, Cont, [], sequential).

% ==========================================================================
% Tests: extract_menu_choices/4
% ==========================================================================

:- begin_tests(extract_menu_choices).

test(single_ite_gives_one_choice) :-
    V = _,
    Body = norm_if_then_else(norm_goal(V = "1"), norm_output(writeln(a)),
                             norm_output(writeln(other))),
    extract_menu_choices(Body, V, Choices, _InvalidAction),
    length(Choices, 1).

test(single_ite_value_is_literal) :-
    V = _,
    Body = norm_if_then_else(norm_goal(V = "1"), norm_output(writeln(a)),
                             norm_output(writeln(other))),
    extract_menu_choices(Body, V, [menu_choice(Val, _)], _),
    Val = "1".

test(nested_ite_gives_multiple_choices) :-
    V = _,
    Body = norm_if_then_else(norm_goal(V = "1"), norm_output(writeln(a)),
           norm_if_then_else(norm_goal(V = "2"), norm_output(writeln(b)),
                             norm_output(writeln(other)))),
    extract_menu_choices(Body, V, Choices, _),
    length(Choices, 2).

test(choices_preserve_order) :-
    V = _,
    Body = norm_if_then_else(norm_goal(V = "1"), norm_output(writeln(a)),
           norm_if_then_else(norm_goal(V = "2"), norm_output(writeln(b)),
                             norm_output(writeln(c)))),
    extract_menu_choices(Body, V, [menu_choice(V1, _), menu_choice(V2, _)], _),
    V1 = "1", V2 = "2".

test(else_arm_without_goal_is_none) :-
    V = _,
    Body = norm_if_then_else(norm_goal(V = "1"), norm_output(writeln(a)),
                             norm_output(writeln(invalid))),
    extract_menu_choices(Body, V, _, InvalidAction),
    InvalidAction = none.

test(else_arm_with_goal_is_retry) :-
    V = _,
    Body = norm_if_then_else(norm_goal(V = "1"), norm_output(writeln(a)),
                             norm_goal(recursive_call)),
    extract_menu_choices(Body, V, _, InvalidAction),
    InvalidAction = retry.

test(else_arm_with_output_then_goal_is_retry) :-
    V = _,
    Body = norm_if_then_else(norm_goal(V = "1"), norm_output(writeln(a)),
                             norm_conj(norm_output(writeln(invalid)),
                                       norm_goal(retry_call))),
    extract_menu_choices(Body, V, _, InvalidAction),
    InvalidAction = retry.

test(non_var_condition_ends_chain) :-
    V = _,
    Body = norm_if_then_else(norm_goal(V = "1"), norm_output(writeln(a)),
           norm_if_then_else(norm_goal(other_goal), norm_output(writeln(b)),
                             norm_output(writeln(c)))),
    extract_menu_choices(Body, V, Choices, _),
    length(Choices, 1).

test(strict_equality_also_recognised) :-
    V = _,
    Body = norm_if_then_else(norm_goal(V == "1"), norm_output(writeln(a)),
                             norm_output(writeln(other))),
    extract_menu_choices(Body, V, [menu_choice("1", _)], _none).

test(reversed_operands_recognised) :-
    V = _,
    Body = norm_if_then_else(norm_goal("1" = V), norm_output(writeln(a)),
                             norm_output(writeln(other))),
    extract_menu_choices(Body, V, [menu_choice("1", _)], _none).

:- end_tests(extract_menu_choices).

% ==========================================================================
% Tests: is_menu_checkpoint/4 — detection
% ==========================================================================

:- begin_tests(is_menu_checkpoint).

test(menu_checkpoint_detected) :-
    build_menu_checkpoint(CP, VN, _ChoiceVar),
    is_menu_checkpoint(CP, VN, _Choices, _InvalidAction).

test(non_menu_checkpoint_not_detected) :-
    build_non_menu_checkpoint(CP, VN),
    \+ is_menu_checkpoint(CP, VN, _, _).

test(menu_choices_count_three) :-
    build_menu_checkpoint(CP, VN, _),
    is_menu_checkpoint(CP, VN, Choices, _),
    length(Choices, 3).

test(menu_choices_have_correct_values) :-
    build_menu_checkpoint(CP, VN, _),
    is_menu_checkpoint(CP, VN, Choices, _),
    maplist([menu_choice(V, _)]>>(true), Choices),
    Choices = [menu_choice("1", _), menu_choice("2", _), menu_choice("3", _)].

test(menu_labels_enriched_from_prompts) :-
    build_menu_checkpoint(CP, VN, _),
    is_menu_checkpoint(CP, VN, Choices, _),
    % "1. Alpha" is the prompt starting with "1."; should become the label.
    member(menu_choice("1", Label), Choices),
    Label = '1. Alpha'.

test(menu_all_labels_enriched) :-
    build_menu_checkpoint(CP, VN, _),
    is_menu_checkpoint(CP, VN, Choices, _),
    Choices = [ menu_choice("1", '1. Alpha'),
                menu_choice("2", '2. Beta'),
                menu_choice("3", '3. Gamma')
              ].

test(menu_invalid_action_none_when_no_goal) :-
    build_menu_checkpoint(CP, VN, _),
    is_menu_checkpoint(CP, VN, _, InvalidAction),
    InvalidAction = none.

test(menu_invalid_action_retry_when_goal_present) :-
    build_retry_checkpoint(CP, VN),
    is_menu_checkpoint(CP, VN, _, InvalidAction),
    InvalidAction = retry.

test(quit_item_detected_as_choice) :-
    build_quit_checkpoint(CP, VN),
    is_menu_checkpoint(CP, VN, Choices, _),
    member(menu_choice("q", _), Choices).

test(quit_label_from_prompt) :-
    build_quit_checkpoint(CP, VN),
    is_menu_checkpoint(CP, VN, Choices, _),
    member(menu_choice("q", Label), Choices),
    Label = 'q. Quit'.

test(single_choice_detected_as_menu) :-
    build_single_choice_checkpoint(CP, VN),
    is_menu_checkpoint(CP, VN, Choices, _),
    length(Choices, 1).

test(anon_var_checkpoint_not_detected) :-
    V = _,
    VN = [],
    Prompts = [norm_output(writeln('1. Yes'))],
    Cont = norm_if_then_else(norm_goal(V = "1"),
                             norm_output(writeln(yes)),
                             norm_output(writeln(no))),
    CP = checkpoint(1, read_string, anon, Prompts, Cont, [], sequential),
    \+ is_menu_checkpoint(CP, VN, _, _).

test(read_password_not_detected_as_menu) :-
    V = _,
    VN = ['Pass' = V],
    Prompts = [norm_output(writeln('1. Option'))],
    Cont = norm_output(writeln(done)),
    CP = checkpoint(1, read_password, 'Pass', Prompts, Cont, [], sequential),
    \+ is_menu_checkpoint(CP, VN, _, _).

:- end_tests(is_menu_checkpoint).

% ==========================================================================
% Tests: menu_input_kind/2
% ==========================================================================

:- begin_tests(menu_input_kind).

test(one_choice_is_radio) :-
    menu_input_kind([menu_choice("1", a)], radio).

test(two_choices_are_radio) :-
    menu_input_kind([menu_choice("1", a), menu_choice("2", b)], radio).

test(four_choices_are_radio) :-
    Choices = [menu_choice("1", a), menu_choice("2", b),
               menu_choice("3", c), menu_choice("4", d)],
    menu_input_kind(Choices, radio).

test(five_choices_are_select) :-
    Choices = [menu_choice("1", a), menu_choice("2", b), menu_choice("3", c),
               menu_choice("4", d), menu_choice("5", e)],
    menu_input_kind(Choices, select).

test(large_menu_is_select) :-
    numlist(1, 10, Ns),
    maplist([N, menu_choice(N, N)]>>true, Ns, Choices),
    menu_input_kind(Choices, select).

:- end_tests(menu_input_kind).

% ==========================================================================
% Tests: build_menu_input/4
% ==========================================================================

:- begin_tests(build_menu_input).

test(radio_produces_span_per_choice) :-
    Choices = [menu_choice("1", '1. A'), menu_choice("2", '2. B')],
    build_menu_input(radio, 'Choice', Choices, Fields),
    length(Fields, 2).

test(radio_field_is_span) :-
    build_menu_input(radio, 'C', [menu_choice("1", a)], [Field]),
    Field = span([], _).

test(radio_span_contains_input_element) :-
    build_menu_input(radio, 'C', [menu_choice("1", a)], [span([], Children)]),
    member(input(Attrs), Children),
    member(type=radio, Attrs).

test(radio_input_has_correct_name) :-
    build_menu_input(radio, 'MyChoice', [menu_choice("1", a)],
                     [span([], Children)]),
    member(input(Attrs), Children),
    member(name='MyChoice', Attrs).

test(radio_input_has_correct_value) :-
    build_menu_input(radio, 'C', [menu_choice("42", lbl)], [span([], Children)]),
    member(input(Attrs), Children),
    member(value="42", Attrs).

test(radio_span_contains_label) :-
    build_menu_input(radio, 'C', [menu_choice("1", 'Option A')],
                     [span([], Children)]),
    member('Option A', Children).

test(select_produces_single_element) :-
    Choices = [menu_choice("1", a), menu_choice("2", b)],
    build_menu_input(select, 'Choice', Choices, [Select]),
    Select = select(_, _).

test(select_has_correct_name) :-
    build_menu_input(select, 'Pick', [menu_choice("1", a)], [select(Attrs, _)]),
    member(name='Pick', Attrs).

test(select_options_match_choices) :-
    Choices = [menu_choice("1", '1. A'), menu_choice("2", '2. B')],
    build_menu_input(select, 'C', Choices, [select(_, Options)]),
    length(Options, 2),
    Options = [option([value="1"], '1. A'), option([value="2"], '2. B')].

test(buttons_produce_one_per_choice) :-
    Choices = [menu_choice("1", a), menu_choice("2", b), menu_choice("3", c)],
    build_menu_input(buttons, 'Choice', Choices, Fields),
    length(Fields, 3).

test(button_is_submit_type) :-
    build_menu_input(buttons, 'C', [menu_choice("1", lbl)], [Button]),
    Button = button(Attrs, _),
    member(type=submit, Attrs).

test(button_has_correct_value) :-
    build_menu_input(buttons, 'C', [menu_choice("x", lbl)], [Button]),
    Button = button(Attrs, _),
    member(value="x", Attrs).

test(button_label_is_content) :-
    build_menu_input(buttons, 'C', [menu_choice("1", 'Click me')], [Button]),
    Button = button(_, 'Click me').

:- end_tests(build_menu_input).

% ==========================================================================
% Tests: generate_menu_form/8
% ==========================================================================

:- begin_tests(generate_menu_form).

test(form_has_method_post) :-
    generate_menu_form([], 'C', [menu_choice("1", a)], [], step_1, radio, [],
                       Form),
    Form = form([method=post | _], _).

test(form_action_targets_next_step) :-
    generate_menu_form([], 'C', [menu_choice("1", a)], [], step_3, radio, [],
                       Form),
    Form = form(Attrs, _),
    member(action='/step_3', Attrs).

test(form_contains_radio_inputs) :-
    Choices = [menu_choice("1", '1. A'), menu_choice("2", '2. B')],
    generate_menu_form([], 'Choice', Choices, [], step_1, radio, [], Form),
    Form = form(_, Children),
    member(span([], [input(RadioAttrs), _]), Children),
    member(type=radio, RadioAttrs).

test(form_radio_includes_submit_button) :-
    generate_menu_form([], 'C', [menu_choice("1", a)], [], step_1, radio, [],
                       form(_, Children)),
    member(input(SubmitAttrs), Children),
    member(type=submit, SubmitAttrs).

test(form_select_includes_submit_button) :-
    generate_menu_form([], 'C', [menu_choice("1", a)], [], step_1, select, [],
                       form(_, Children)),
    member(input(SubmitAttrs), Children),
    member(type=submit, SubmitAttrs).

test(form_buttons_no_extra_submit) :-
    % buttons InputKind: each button IS a submit; no extra input[type=submit].
    Choices = [menu_choice("1", a), menu_choice("2", b)],
    generate_menu_form([], 'C', Choices, [], step_1, buttons, [],
                       form(_, Children)),
    include([input(A)]>>(member(type=submit, A)), Children, SubmitInputs),
    SubmitInputs = [].

test(form_with_prompts_includes_prompt_html) :-
    Prompts = [norm_output(writeln('Choose:'))],
    generate_menu_form(Prompts, 'C', [menu_choice("1", a)], [], step_1, radio,
                       [], form(_, Children)),
    member(p('Choose:'), Children).

test(form_with_hidden_fields) :-
    V = _,
    VN = ['Prev' = V],
    generate_menu_form([], 'C', [menu_choice("1", a)], ['Prev'], step_2,
                       radio, VN, form(_, Children)),
    member(input(HAttr), Children),
    member(type=hidden, HAttr),
    member(name='Prev', HAttr).

test(form_child_order_hidden_before_menu_input) :-
    V = _,
    VN = ['Prev' = V],
    Choices = [menu_choice("1", a)],
    generate_menu_form([], 'C', Choices, ['Prev'], step_2, radio, VN,
                       form(_, Children)),
    nth1(HidIdx, Children, input(HAttr)), member(type=hidden, HAttr), !,
    nth1(SpanIdx, Children, span([], _)), !,
    HidIdx < SpanIdx.

:- end_tests(generate_menu_form).

% ==========================================================================
% Tests: integration — numbered selection flow
% ==========================================================================

:- begin_tests(menu_integration_numbered_selection).

%% Helper: build a 3-choice menu with retry on invalid input.
build_menu_body(Body, VN) :-
    V = _,
    VN = ['Choice' = V],
    Body = norm_conj(
        norm_output(writeln('1. Do A')),
        norm_conj(
            norm_output(writeln('2. Do B')),
            norm_conj(
                norm_output(writeln('3. Do C')),
                norm_conj(
                    norm_output(writeln('Pick 1-3:')),
                    norm_conj(
                        norm_read_string(user, "\n", "\r", _, V),
                        norm_if_then_else(
                            norm_goal(V = "1"),
                            norm_output(writeln('A done')),
                            norm_if_then_else(
                                norm_goal(V = "2"),
                                norm_output(writeln('B done')),
                                norm_if_then_else(
                                    norm_goal(V = "3"),
                                    norm_output(writeln('C done')),
                                    norm_output(writeln('Invalid'))
                                )
                            )
                        )
                    )
                )
            )
        )
    ).

test(menu_body_produces_two_steps) :-
    build_menu_body(Body, VN),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, Steps),
    length(Steps, 2).

test(menu_step_0_has_menu_resp) :-
    build_menu_body(Body, VN),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, _, _, _, _)).

test(menu_step_0_var_name_is_choice) :-
    build_menu_body(Body, VN),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, menu_resp(_, 'Choice', _, _, _, _)).

test(menu_step_0_has_three_choices) :-
    build_menu_body(Body, VN),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, Choices, _, _, _)),
    length(Choices, 3).

test(menu_step_0_choice_values) :-
    build_menu_body(Body, VN),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, Choices, _, _, _)),
    Choices = [menu_choice("1", _), menu_choice("2", _), menu_choice("3", _)].

test(menu_step_0_labels_from_prompts) :-
    build_menu_body(Body, VN),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, Choices, _, _, _)),
    member(menu_choice("1", '1. Do A'), Choices),
    member(menu_choice("2", '2. Do B'), Choices),
    member(menu_choice("3", '3. Do C'), Choices).

test(menu_step_0_input_kind_is_radio) :-
    build_menu_body(Body, VN),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, _, _, _, radio)).

test(menu_step_0_posts_to_step_1) :-
    build_menu_body(Body, VN),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, _, _, step_1, _)).

test(menu_step_1_has_cond_resp) :-
    build_menu_body(Body, VN),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, _)).

:- end_tests(menu_integration_numbered_selection).

% ==========================================================================
% Tests: quit (q) behaviour
% ==========================================================================

:- begin_tests(menu_quit_behaviour).

test(quit_choice_included_in_choices) :-
    build_quit_checkpoint(CP, VN),
    is_menu_checkpoint(CP, VN, Choices, _),
    member(menu_choice("q", _), Choices).

test(quit_label_preserved) :-
    build_quit_checkpoint(CP, VN),
    is_menu_checkpoint(CP, VN, Choices, _),
    member(menu_choice("q", 'q. Quit'), Choices).

test(quit_choice_in_menu_resp) :-
    V = _,
    VN = ['Choice' = V],
    Body = norm_conj(
        norm_output(writeln('1. Start')),
        norm_conj(
            norm_output(writeln('q. Quit')),
            norm_conj(
                norm_read_string(user, "\n", "\r", _, V),
                norm_if_then_else(
                    norm_goal(V = "1"),
                    norm_output(writeln(started)),
                    norm_if_then_else(
                        norm_goal(V = "q"),
                        norm_output(writeln(goodbye)),
                        norm_output(writeln(invalid))
                    )
                )
            )
        )
    ),
    detect_checkpoints(Body, VN, CPs),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, Choices, _, _, _)),
    member(menu_choice("q", _), Choices).

:- end_tests(menu_quit_behaviour).

% ==========================================================================
% Tests: re-display on invalid input (retry detection)
% ==========================================================================

:- begin_tests(menu_retry_on_invalid).

test(retry_detected_in_checkpoint) :-
    build_retry_checkpoint(CP, VN),
    is_menu_checkpoint(CP, VN, _, InvalidAction),
    InvalidAction = retry.

test(retry_body_generates_retry_resp) :-
    V = _,
    VN = ['Choice' = V],
    Body = norm_conj(
        norm_output(writeln('1. Option A')),
        norm_conj(
            norm_output(writeln('2. Option B')),
            norm_conj(
                norm_read_string(user, "\n", "\r", _, V),
                norm_if_then_else(
                    norm_goal(V = "1"),
                    norm_output(writeln(a)),
                    norm_if_then_else(
                        norm_goal(V = "2"),
                        norm_output(writeln(b)),
                        norm_conj(
                            norm_output(writeln('Invalid')),
                            norm_goal(retry_loop)
                        )
                    )
                )
            )
        )
    ),
    detect_checkpoints(Body, VN, retry_loop/0, CPs),
    extract_continuations(CPs, VN, retry_loop/0, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, ElseResp)),
    % The else arm of the outermost cond_resp should eventually contain retry.
    response_contains_retry(ElseResp, step_0).

test(non_menu_checkpoint_not_affected_by_retry_detection) :-
    build_non_menu_checkpoint(CP, VN),
    \+ is_menu_checkpoint(CP, VN, _, _).

:- end_tests(menu_retry_on_invalid).

% ==========================================================================
% Integration: auth_example.pl
% ==========================================================================

:- begin_tests(auth_menu_integration).

auth_menu_steps(Steps, VN) :-
    mr_test_dir(Dir),
    atomic_list_concat([Dir, '/../examples/auth_example.pl'], AuthFile),
    read_and_normalise(AuthFile, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, main/0, CPs),
    extract_continuations(CPs, VN, main/0, Steps).

test(auth_step_0_is_menu_resp) :-
    auth_menu_steps([Step0 | _], _),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, _, _, _, _)).

test(auth_step_0_choice_var_name) :-
    auth_menu_steps([Step0 | _], _),
    Step0 = cont_step(step_0, _, _, menu_resp(_, 'Choice', _, _, _, _)).

test(auth_step_0_has_three_choices) :-
    auth_menu_steps([Step0 | _], _),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, Choices, _, _, _)),
    length(Choices, 3).

test(auth_menu_input_kind_is_radio) :-
    auth_menu_steps([Step0 | _], _),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, _, _, _, radio)).

test(auth_choice_values_are_1_2_3) :-
    auth_menu_steps([Step0 | _], _),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, Choices, _, _, _)),
    Choices = [menu_choice("1", _), menu_choice("2", _), menu_choice("3", _)].

test(auth_labels_from_prompts) :-
    auth_menu_steps([Step0 | _], _),
    Step0 = cont_step(step_0, _, _, menu_resp(_, _, Choices, _, _, _)),
    member(menu_choice("1", '1. Register'), Choices),
    member(menu_choice("2", '2. Login'),    Choices),
    member(menu_choice("3", '3. Forgot Password'), Choices).

test(auth_step_1_still_cond_resp) :-
    auth_menu_steps([_, Step1 | _], _),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, _)).

test(auth_invalid_choice_retry_preserved) :-
    auth_menu_steps(Steps, _),
    member(Step, Steps),
    Step = cont_step(_, _, _, Response),
    response_contains_retry(Response, step_0).

:- end_tests(auth_menu_integration).

% ==========================================================================
% Helper (re-used from test_continuation_extractor.pl)
% ==========================================================================

response_contains_retry(retry_resp(T), T) :- !.
response_contains_retry(cond_resp(_, ThenR, ElseR), T) :-
    ( response_contains_retry(ThenR, T) -> true
    ; response_contains_retry(ElseR, T)
    ).
response_contains_retry(_, _) :- fail.
