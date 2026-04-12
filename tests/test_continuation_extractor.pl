%% tests/test_continuation_extractor.pl
%%
%% Unit and integration tests for the Stage 4 continuation extraction engine
%% (src/continuation_extractor.pl).
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_continuation_extractor.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_continuation_extractor].
%%   ?- run_tests.

:- use_module('../src/continuation_extractor').
:- use_module('../src/checkpoint_detector').
:- use_module('../src/reader').
:- use_module(library(plunit)).
:- use_module(library(lists)).

% Capture the test directory at load time so integration tests can locate
% sibling files reliably.
:- prolog_load_context(directory, Dir),
   assert(ce_test_dir(Dir)).

% ==========================================================================
% Helper: build a norm_conj chain from a flat list of normalised goals
% ==========================================================================

list_to_nc([], norm_true).
list_to_nc([G], G) :- !.
list_to_nc([G | Rest], norm_conj(G, Tail)) :-
    list_to_nc(Rest, Tail).

% ==========================================================================
% Tests: cont_step_name/2
% ==========================================================================

:- begin_tests(cont_step_name).

test(step_0_is_step_0) :-
    cont_step_name(0, step_0).

test(step_1_is_step_1) :-
    cont_step_name(1, step_1).

test(step_10_is_step_10) :-
    cont_step_name(10, step_10).

:- end_tests(cont_step_name).

% ==========================================================================
% Tests: extract_continuations/4 — empty input
% ==========================================================================

:- begin_tests(extract_continuations_empty).

test(no_checkpoints_gives_no_steps) :-
    extract_continuations([], [], none, Steps),
    Steps = [].

:- end_tests(extract_continuations_empty).

% ==========================================================================
% Tests: extract_continuations/4 — sequential two-step flow
% ==========================================================================

:- begin_tests(extract_continuations_sequential).

%% Build the two-read body:
%%   writeln(p1), read Name, writeln(p2), read Age, format(result).
%
% Helper creates CPs so we can run the extractor.
two_read_body_cps(CPs, VN) :-
    V1 = _, V2 = _,
    VN = ['Name' = V1, 'Age' = V2],
    list_to_nc(
        [ norm_output(writeln('Enter name:')),
          norm_read_string(user, "\n", "\r", _, V1),
          norm_output(writeln('Enter age:')),
          norm_read_string(user, "\n", "\r", _, V2),
          norm_output(format("Hello ~w ~w~n", [V1, V2]))
        ], Body),
    detect_checkpoints(Body, VN, CPs).

test(sequential_produces_three_steps) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, Steps),
    length(Steps, 3).

test(step_0_is_first) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, _).

test(step_0_has_no_recv_vars) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, RecvVars, _, _),
    RecvVars = [].

test(step_0_has_form_resp) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, form_resp(_, _, _, _, _)).

test(step_0_asks_for_name) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, form_resp(_, InputVarName, _, _, _)),
    InputVarName = 'Name'.

test(step_0_posts_to_step_1) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [Step0 | _]),
    Step0 = cont_step(step_0, _, _, form_resp(_, _, _, NextStep, _)),
    NextStep = step_1.

test(step_1_is_second) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, _, _, _).

test(step_1_receives_name) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, RecvVars, _, _),
    memberchk('Name', RecvVars).

test(step_1_has_form_resp_for_age) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, _, _, form_resp(_, 'Age', _, step_2, _)).

test(step_1_carries_name_in_hidden) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, _, _, form_resp(_, _, HiddenVars, _, _)),
    memberchk('Name', HiddenVars).

test(step_2_is_last) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, _, Step2]),
    Step2 = cont_step(step_2, _, _, _).

test(step_2_receives_name_and_age) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, _, Step2]),
    Step2 = cont_step(step_2, RecvVars, _, _),
    memberchk('Name', RecvVars),
    memberchk('Age',  RecvVars).

test(step_2_has_result_resp) :-
    two_read_body_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, _, Step2]),
    Step2 = cont_step(step_2, _, _, result_resp(_, _)).

:- end_tests(extract_continuations_sequential).

% ==========================================================================
% Tests: extract_continuations/4 — single read with if-then-else continuation
% ==========================================================================

:- begin_tests(extract_continuations_branch).

%% Body: read Choice; if valid -> done ; else -> output error.
one_read_branch_cps(CPs, VN) :-
    V = _,
    VN = ['Choice' = V],
    list_to_nc(
        [ norm_output(writeln('Enter choice:')),
          norm_read_string(user, "\n", "\r", _, V),
          norm_if_then_else(
              norm_goal(V = "yes"),
              norm_output(writeln(accepted)),
              norm_output(writeln(rejected))
          )
        ], Body),
    detect_checkpoints(Body, VN, CPs).

test(branch_produces_two_steps) :-
    one_read_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, Steps),
    length(Steps, 2).

test(step_1_has_cond_resp) :-
    one_read_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, _)).

test(cond_resp_has_result_then) :-
    one_read_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, ThenResp, _)),
    ThenResp = result_resp(_, _).

test(cond_resp_has_result_else) :-
    one_read_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, ElseResp)),
    ElseResp = result_resp(_, _).

:- end_tests(extract_continuations_branch).

% ==========================================================================
% Tests: extract_continuations/4 — retry loop
% ==========================================================================

:- begin_tests(extract_continuations_retry).

%% Body: read Choice; if valid -> done ; else -> recursive call to loop/0.
retry_loop_cps(CPs, VN) :-
    V = _,
    VN = ['Choice' = V],
    list_to_nc(
        [ norm_output(writeln('Pick 1 or 2:')),
          norm_read_string(user, "\n", "\r", _, V),
          norm_if_then_else(
              norm_goal(member(V, ["1", "2"])),
              norm_output(format("You chose: ~w~n", [V])),
              norm_goal(loop)
          )
        ], Body),
    detect_checkpoints(Body, VN, loop/0, CPs).

test(retry_produces_two_steps) :-
    retry_loop_cps(CPs, VN),
    extract_continuations(CPs, VN, loop/0, Steps),
    length(Steps, 2).

test(retry_step_1_has_cond_resp) :-
    retry_loop_cps(CPs, VN),
    extract_continuations(CPs, VN, loop/0, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, _)).

test(retry_else_is_retry_resp) :-
    retry_loop_cps(CPs, VN),
    extract_continuations(CPs, VN, loop/0, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, ElseResp)),
    ElseResp = retry_resp(step_0).

test(retry_then_is_result_resp) :-
    retry_loop_cps(CPs, VN),
    extract_continuations(CPs, VN, loop/0, [_, Step1]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, ThenResp, _)),
    ThenResp = result_resp(_, _).

%% A bare recursive call as the entire continuation body.
bare_retry_cps(CPs, VN) :-
    V = _,
    VN = ['X' = V],
    Body = norm_conj(
        norm_read_string(user, "\n", "\r", _, V),
        norm_goal(bare_retry)
    ),
    detect_checkpoints(Body, VN, bare_retry/0, CPs).

test(bare_retry_continuation_is_retry_resp) :-
    bare_retry_cps(CPs, VN),
    extract_continuations(CPs, VN, bare_retry/0, Steps),
    Steps = [Step0, Step1],
    Step1 = cont_step(step_1, _, _, retry_resp(step_0)).

:- end_tests(extract_continuations_retry).

% ==========================================================================
% Tests: extract_continuations/4 — pre-goals (compute goals before next read)
% ==========================================================================

:- begin_tests(extract_continuations_pre_goals).

%% Body: read V1, compute something, read V2.
%% The compute goal should appear as a PreGoal in step_1.
pre_goal_cps(CPs, VN) :-
    V1 = _, V2 = _,
    VN = ['Input' = V1, 'Result' = V2],
    list_to_nc(
        [ norm_read_string(user, "\n", "\r", _, V1),
          norm_goal(transform(V1, V2)),
          norm_output(writeln('Enter result:')),
          norm_read_string(user, "\n", "\r", _, V2)
        ], Body),
    detect_checkpoints(Body, VN, CPs).

test(step_1_has_pre_goal) :-
    pre_goal_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, _, PreGoals, _),
    memberchk(norm_goal(transform(_, _)), PreGoals).

:- end_tests(extract_continuations_pre_goals).

% ==========================================================================
% Tests: extract_continuations/4 — menu with reads in both branches
% ==========================================================================

:- begin_tests(extract_continuations_menu_two_branches).

%% Body: read Choice; ( Choice = a -> read A, use(A) ; read B, use(B) ).
menu_two_branch_cps(CPs, VN) :-
    Va = _, Vb = _, Vc = _,
    VN = ['Choice' = Va, 'A' = Vb, 'B' = Vc],
    list_to_nc(
        [ norm_output(writeln('a or b?')),
          norm_read_string(user, "\n", "\r", _, Va),
          norm_if_then_else(
              norm_goal(Va = "a"),
              norm_conj(
                  norm_output(writeln('A value:')),
                  norm_conj(
                      norm_read_string(user, "\n", "\r", _, Vb),
                      norm_output(format("A=~w~n", [Vb]))
                  )
              ),
              norm_conj(
                  norm_output(writeln('B value:')),
                  norm_conj(
                      norm_read_string(user, "\n", "\r", _, Vc),
                      norm_output(format("B=~w~n", [Vc]))
                  )
              )
          )
        ], Body),
    detect_checkpoints(Body, VN, CPs).

test(menu_two_branch_three_checkpoints) :-
    menu_two_branch_cps(CPs, _VN),
    length(CPs, 3).

test(menu_two_branch_four_steps) :-
    menu_two_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, Steps),
    length(Steps, 4).

test(menu_step_1_has_cond_resp) :-
    menu_two_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, _)).

test(menu_cond_then_is_form_resp) :-
    menu_two_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, ThenResp, _)),
    ThenResp = form_resp(_, _, _, _, _).

test(menu_cond_else_is_form_resp) :-
    menu_two_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, ElseResp)),
    ElseResp = form_resp(_, _, _, _, _).

test(menu_then_form_posts_to_step_2) :-
    menu_two_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, form_resp(_, _, _, ThenNext, _), _)),
    ThenNext = step_2.

test(menu_else_form_posts_to_step_3) :-
    menu_two_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, Step1 | _]),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, form_resp(_, _, _, ElseNext, _))),
    ElseNext = step_3.

test(menu_step_2_has_result_resp) :-
    menu_two_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, _, Step2 | _]),
    Step2 = cont_step(step_2, _, _, result_resp(_, _)).

test(menu_step_3_has_result_resp) :-
    menu_two_branch_cps(CPs, VN),
    extract_continuations(CPs, VN, none, [_, _, _, Step3]),
    Step3 = cont_step(step_3, _, _, result_resp(_, _)).

:- end_tests(extract_continuations_menu_two_branches).

% ==========================================================================
% Integration tests: auth_example.pl — register/login/forgot-password
% ==========================================================================

:- begin_tests(auth_integration).

%% Parse auth_example.pl and run the full Stage 3 + Stage 4 pipeline.

auth_file(File) :-
    ce_test_dir(Dir),
    file_directory_name(Dir, RepoRoot),
    atomic_list_concat([RepoRoot, '/examples/auth_example.pl'], File).

auth_steps(Steps, VN) :-
    auth_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, main/0, CPs),
    extract_continuations(CPs, VN, main/0, Steps).

%% auth_example.pl has 7 read_string calls → 7 checkpoints → 8 steps.
test(auth_produces_eight_steps) :-
    auth_steps(Steps, _),
    length(Steps, 8).

%% The first step is the entry GET handler.
test(auth_step_0_is_entry) :-
    auth_steps([cont_step(step_0, [], _, _) | _], _).

%% step_0 asks for the menu Choice via a menu_resp (Stage 9).
test(auth_step_0_asks_for_choice) :-
    auth_steps([Step0 | _], _),
    Step0 = cont_step(step_0, _, _, menu_resp(_, 'Choice', _, _, step_1, _)).

%% step_1 dispatches on the menu choice (cond_resp).
test(auth_step_1_has_cond_resp) :-
    auth_steps([_, Step1 | _], _),
    Step1 = cont_step(step_1, _, _, cond_resp(_, _, _)).

%% step_1 receives the Choice variable.
test(auth_step_1_receives_choice) :-
    auth_steps([_, Step1 | _], _),
    Step1 = cont_step(step_1, RecvVars, _, _),
    memberchk('Choice', RecvVars).

%% The then-arm of step_1 is a form asking for Username (Register flow).
test(auth_step_1_then_is_form_for_username) :-
    auth_steps([_, Step1 | _], _),
    Step1 = cont_step(step_1, _, _, cond_resp(_, ThenResp, _)),
    ThenResp = form_resp(_, 'Username', _, _, _).

%% The register flow leads to step_2 (Username) → step_3 (Password) → step_4 (Email) → result.
test(auth_register_then_arm_posts_to_step_2) :-
    auth_steps([_, Step1 | _], _),
    Step1 = cont_step(step_1, _, _, cond_resp(_, form_resp(_, _, _, step_2, _), _)).

%% step_2 (Username in Register) posts to step_3 (Password).
test(auth_step_2_posts_to_step_3) :-
    auth_steps(Steps, _),
    nth1(3, Steps, Step2),
    Step2 = cont_step(step_2, _, _, form_resp(_, 'Password', _, step_3, _)).

%% step_3 (Password in Register) posts to step_4 (Email).
test(auth_step_3_posts_to_step_4) :-
    auth_steps(Steps, _),
    nth1(4, Steps, Step3),
    Step3 = cont_step(step_3, _, _, form_resp(_, 'Email', _, step_4, _)).

%% step_4 is the Register result step.
test(auth_step_4_is_result) :-
    auth_steps(Steps, _),
    nth1(5, Steps, Step4),
    Step4 = cont_step(step_4, _, _, result_resp(_, _)).

%% The retry (invalid choice) branch generates a retry_resp.
test(auth_invalid_choice_generates_retry) :-
    auth_steps(Steps, _),
    % Find the cond_resp in step_1 and search recursively for retry_resp.
    member(Step, Steps),
    Step = cont_step(_, _, _, Response),
    response_contains_retry(Response, step_0).

%% The login flow (Choice = "2") posts first to step_5 (Username).
test(auth_login_branch_posts_to_step_5) :-
    auth_steps(Steps, _),
    nth1(2, Steps, Step1),
    Step1 = cont_step(step_1, _, _, Resp),
    find_step_in_response(Resp, step_5).

%% step_6 (Login Password) is a result step.
test(auth_step_6_is_result) :-
    auth_steps(Steps, _),
    nth1(7, Steps, Step6),
    Step6 = cont_step(step_6, _, _, result_resp(_, _)).

%% step_7 is the Forgot Password result step.
test(auth_step_7_is_result) :-
    auth_steps(Steps, _),
    nth1(8, Steps, Step7),
    Step7 = cont_step(step_7, _, _, result_resp(_, _)).

:- end_tests(auth_integration).

% ==========================================================================
% Integration test: write_cont_steps produces valid output
% ==========================================================================

:- begin_tests(write_cont_steps_integration).

test(write_cont_steps_produces_output) :-
    ce_test_dir(Dir),
    file_directory_name(Dir, RepoRoot),
    atomic_list_concat([RepoRoot, '/examples/auth_example.pl'], File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, main/0, CPs),
    extract_continuations(CPs, VN, main/0, Steps),
    tmp_file_stream(text, TmpFile, TmpStream),
    close(TmpStream),
    setup_call_cleanup(
        true,
        ( open(TmpFile, write, Out),
          write_cont_steps(Out, Steps, VN),
          close(Out),
          % Read it back and verify structural elements
          open(TmpFile, read, In),
          read_all_lines(In, Lines),
          close(In),
          assert_output_structure(Lines)
        ),
        ( exists_file(TmpFile) -> delete_file(TmpFile) ; true )
    ).

assert_output_structure(Lines) :-
    lines_contain(Lines, 'step_0'),
    lines_contain(Lines, 'step_1'),
    lines_contain(Lines, 'http_handler'),
    lines_contain(Lines, 'http_parameters'),
    lines_contain(Lines, 'reply_html_page').

lines_contain(Lines, Sub) :-
    member(Line, Lines),
    sub_atom(Line, _, _, _, Sub), !.

read_all_lines(S, Lines) :-
    read_line_to_string(S, Line),
    ( Line == end_of_file ->
        Lines = []
    ;   atom_string(LineAtom, Line),
        Lines = [LineAtom | Rest],
        read_all_lines(S, Rest)
    ).

:- end_tests(write_cont_steps_integration).

% ==========================================================================
% Helpers used by the integration tests
% ==========================================================================

%% response_contains_retry(+Response, +TargetStep) is semidet.
%  True when Response (or any nested sub-response) is retry_resp(TargetStep).
response_contains_retry(retry_resp(T), T) :- !.
response_contains_retry(cond_resp(_, ThenR, ElseR), T) :-
    ( response_contains_retry(ThenR, T) -> true
    ; response_contains_retry(ElseR, T)
    ).
response_contains_retry(form_resp(_, _, _, _, _), _) :- fail.
response_contains_retry(menu_resp(_, _, _, _, _, _), _) :- fail.
response_contains_retry(result_resp(_, _),     _) :- fail.

%% find_step_in_response(+Response, +StepName) is semidet.
%  True when at least one form_resp or menu_resp in Response posts to StepName.
find_step_in_response(form_resp(_, _, _, Next, _), Next) :- !.
find_step_in_response(menu_resp(_, _, _, _, Next, _), Next) :- !.
find_step_in_response(cond_resp(_, ThenR, ElseR), S) :-
    ( find_step_in_response(ThenR, S) -> true
    ; find_step_in_response(ElseR, S)
    ).
