%% tests/test_integration_server.pl
%%
%% Integration tests for Stage 14: Validation and Tests.
%%
%% These tests cover the full pipeline end-to-end:
%%   1. Converting a source program to a web server program.
%%   2. Loading the generated program into a subprocess.
%%   3. Starting the HTTP server.
%%   4. Confirming the root route responds with HTTP 200.
%%   5. Multi-step flow tests (register, login, forgot password).
%%   6. Invalid input loop / menu redisplay tests.
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_integration_server.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_integration_server].
%%   ?- run_tests.

:- use_module('../src/web_server_generator').
:- use_module('../src/reader').
:- use_module('../src/checkpoint_detector').
:- use_module('../src/continuation_extractor').
:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(process)).
:- use_module(library(http/http_open)).
:- use_module(library(http/http_client)).

% Capture the test directory at load time so integration tests can locate
% sibling files reliably.
:- prolog_load_context(directory, Dir),
   assert(sit_test_dir(Dir)).

% ==========================================================================
% Helpers
% ==========================================================================

%% sit_repo_root(-Root:atom) is det.
%  Return the repository root directory (parent of tests/).
sit_repo_root(Root) :-
    sit_test_dir(Dir),
    file_directory_name(Dir, Root).

%% sit_input_file(+Name:atom, -File:atom) is det.
%  Resolve a file path relative to examples/.
sit_input_file(Name, File) :-
    sit_repo_root(Root),
    atomic_list_concat([Root, '/examples/', Name], File).

%% lines_contain(+Lines:list, +Sub:atom) is semidet.
%  True when at least one line in Lines contains the sub-atom Sub.
lines_contain(Lines, Sub) :-
    member(Line, Lines),
    sub_atom(Line, _, _, _, Sub), !.

%% read_all_lines(+Stream, -Lines:list) is det.
%  Read all lines from Stream as a list of atoms.
read_all_lines(S, Lines) :-
    read_line_to_string(S, Line),
    ( Line == end_of_file ->
        Lines = []
    ;   atom_string(LineAtom, Line),
        Lines = [LineAtom | Rest],
        read_all_lines(S, Rest)
    ).

%% sit_swipl_exe(-Exe:atom) is det.
%  Return the path to the current SWI-Prolog executable.
sit_swipl_exe(Exe) :-
    current_prolog_flag(executable, Exe).

%% wait_for_server(+Port:integer, +MaxTries:integer) is semidet.
%  Poll the server at localhost:Port until it responds or MaxTries is exceeded.
%  Sleeps 0.2 seconds between attempts.
wait_for_server(Port, MaxTries) :-
    MaxTries > 0,
    ( catch(
          ( atomic_list_concat(['http://localhost:', Port, '/'], URL),
            http_get(URL, _, [status_code(_)]) ),
          _,
          fail
      ) ->
        true
    ;   sleep(0.2),
        Tries1 is MaxTries - 1,
        wait_for_server(Port, Tries1)
    ).

%% sit_start_server(+ServerFile:atom, +Port:integer, -PID:integer) is det.
%  Start a SWI-Prolog HTTP server subprocess running ServerFile on Port.
%  The server is started by calling vetusia_server(Port) directly.
sit_start_server(ServerFile, Port, PID) :-
    sit_swipl_exe(Swipl),
    atomic_list_concat([
        'vetusia_server(', Port, '), thread_get_message(_)'
    ], Goal),
    process_create(
        Swipl,
        ['-q', '-g', Goal, '-s', ServerFile],
        [process(PID), stderr(null), stdout(null)]
    ).

%% sit_stop_server(+PID:integer) is det.
%  Terminate the server subprocess identified by PID.
sit_stop_server(PID) :-
    catch(process_kill(PID), _, true),
    catch(process_wait(PID, _), _, true).

%% sit_http_get_status(+URL:atom, -Status:integer, -Body:atom) is det.
%  Perform an HTTP GET request and return the status code and response body.
sit_http_get_status(URL, Status, Body) :-
    http_open(URL, In, [status_code(Status)]),
    read_stream_to_codes(In, Codes),
    close(In),
    atom_codes(Body, Codes).

%% sit_http_post_form(+URL:atom, +Pairs:list, -Status:integer, -Body:atom) is det.
%  Perform an HTTP POST with form-encoded data.
sit_http_post_form(URL, Pairs, Status, Body) :-
    http_open(URL, In,
              [method(post),
               post(form(Pairs)),
               status_code(Status)]),
    read_stream_to_codes(In, Codes),
    close(In),
    atom_codes(Body, Codes).

% ==========================================================================
% Tests: conversion output structure (structural / static)
% ==========================================================================

:- begin_tests(conversion_output_structure).

%% input_example.pl → basic structural checks on the generated file.
test(input_example_produces_valid_output, [
        setup(( sit_input_file('input_example.pl', InFile),
                tmp_file_stream(text, TmpFile, TmpStream),
                close(TmpStream) )),
        cleanup(( exists_file(TmpFile) -> delete_file(TmpFile) ; true ))
    ]) :-
    generate_web_server(InFile, TmpFile),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    % Structural checks
    lines_contain(Lines, 'step_0('),
    lines_contain(Lines, 'step_1('),
    lines_contain(Lines, 'step_2('),
    lines_contain(Lines, 'http_handler'),
    lines_contain(Lines, 'vetusia_server(Port)'),
    lines_contain(Lines, 'initialization(main, main)'),
    lines_contain(Lines, 'reply_html_page'),
    lines_contain(Lines, 'http_parameters').

%% auth_example.pl → all eight step handlers must be present.
test(auth_example_all_steps, [
        setup(( sit_input_file('auth_example.pl', InFile),
                tmp_file_stream(text, TmpFile, TmpStream),
                close(TmpStream) )),
        cleanup(( exists_file(TmpFile) -> delete_file(TmpFile) ; true ))
    ]) :-
    generate_web_server(InFile, TmpFile),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    lines_contain(Lines, 'step_0('),
    lines_contain(Lines, 'step_1('),
    lines_contain(Lines, 'step_2('),
    lines_contain(Lines, 'step_3('),
    lines_contain(Lines, 'step_4('),
    lines_contain(Lines, 'step_5('),
    lines_contain(Lines, 'step_6('),
    lines_contain(Lines, 'step_7(').

%% Variables from the auth example are preserved in the output.
test(auth_example_variables_preserved, [
        setup(( sit_input_file('auth_example.pl', InFile),
                tmp_file_stream(text, TmpFile, TmpStream),
                close(TmpStream) )),
        cleanup(( exists_file(TmpFile) -> delete_file(TmpFile) ; true ))
    ]) :-
    generate_web_server(InFile, TmpFile),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    lines_contain(Lines, 'Choice'),
    lines_contain(Lines, 'Username'),
    lines_contain(Lines, 'Password'),
    lines_contain(Lines, 'Email').

%% The invalid-choice retry branch must generate an http_redirect call.
test(auth_example_retry_redirect_present, [
        setup(( sit_input_file('auth_example.pl', InFile),
                tmp_file_stream(text, TmpFile, TmpStream),
                close(TmpStream) )),
        cleanup(( exists_file(TmpFile) -> delete_file(TmpFile) ; true ))
    ]) :-
    generate_web_server(InFile, TmpFile),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    lines_contain(Lines, 'http_redirect').

%% The auth menu must be rendered as radio buttons (Stage 9 menu recognition).
test(auth_example_menu_radio_buttons, [
        setup(( sit_input_file('auth_example.pl', InFile),
                tmp_file_stream(text, TmpFile, TmpStream),
                close(TmpStream) )),
        cleanup(( exists_file(TmpFile) -> delete_file(TmpFile) ; true ))
    ]) :-
    generate_web_server(InFile, TmpFile),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    lines_contain(Lines, 'type=radio').

%% State serialise/deserialise helpers must be present.
test(auth_example_state_serialise_present, [
        setup(( sit_input_file('auth_example.pl', InFile),
                tmp_file_stream(text, TmpFile, TmpStream),
                close(TmpStream) )),
        cleanup(( exists_file(TmpFile) -> delete_file(TmpFile) ; true ))
    ]) :-
    generate_web_server(InFile, TmpFile),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    lines_contain(Lines, 'state_serialise'),
    lines_contain(Lines, 'state_deserialise').

:- end_tests(conversion_output_structure).

% ==========================================================================
% Tests: live HTTP server — input_example.pl
% ==========================================================================

:- begin_tests(live_server_input_example).

%% Full live-server test: generate, start, confirm root responds, stop.
test(input_example_root_responds, [
        setup(( sit_input_file('input_example.pl', InFile),
                tmp_file_stream(text, TmpFile, TmpStream),
                close(TmpStream),
                Port = 18181,
                generate_web_server(InFile, TmpFile, Port),
                sit_start_server(TmpFile, Port, PID),
                ( wait_for_server(Port, 25) ->
                    nb_setval(sit_ie_pid,     PID),
                    nb_setval(sit_ie_tmpfile, TmpFile)
                ;   sit_stop_server(PID), fail
                ) )),
        cleanup(( nb_getval(sit_ie_pid,     CPID),
                  nb_getval(sit_ie_tmpfile, CTmp),
                  sit_stop_server(CPID),
                  ( exists_file(CTmp) -> delete_file(CTmp) ; true ) ))
    ]) :-
    atomic_list_concat(['http://localhost:18181/'], URL),
    sit_http_get_status(URL, Status, _Body),
    Status =:= 200.

%% Root route response must contain an HTML form.
test(input_example_root_has_form, [
        setup(( sit_input_file('input_example.pl', InFile),
                tmp_file_stream(text, TmpFile2, TmpStream2),
                close(TmpStream2),
                Port2 = 18183,
                generate_web_server(InFile, TmpFile2, Port2),
                sit_start_server(TmpFile2, Port2, PID2),
                ( wait_for_server(Port2, 25) ->
                    nb_setval(sit_ie2_pid,     PID2),
                    nb_setval(sit_ie2_tmpfile, TmpFile2)
                ;   sit_stop_server(PID2), fail
                ) )),
        cleanup(( nb_getval(sit_ie2_pid,     CPID2),
                  nb_getval(sit_ie2_tmpfile, CTmp2),
                  sit_stop_server(CPID2),
                  ( exists_file(CTmp2) -> delete_file(CTmp2) ; true ) ))
    ]) :-
    atomic_list_concat(['http://localhost:18183/'], URL),
    sit_http_get_status(URL, _Status, Body),
    ( sub_atom(Body, _, _, _, '<form')
    ; sub_atom(Body, _, _, _, 'form') ), !.

:- end_tests(live_server_input_example).

% ==========================================================================
% Tests: live HTTP server — auth_example.pl (multi-step flows)
% ==========================================================================

:- begin_tests(live_server_auth_example).

%% Comprehensive live server test: generate, start, exercise all flows, stop.
%% All auth server assertions are in a single test to avoid port conflicts
%% from sequential setup/cleanup cycles between individual tests.
test(auth_server_all_flows, [
        setup(( sit_input_file('auth_example.pl', InFile),
                tmp_file_stream(text, TmpFile, TmpStream),
                close(TmpStream),
                Port = 18182,
                generate_web_server(InFile, TmpFile, Port),
                sit_start_server(TmpFile, Port, PID),
                ( wait_for_server(Port, 25) ->
                    true
                ;   sit_stop_server(PID),
                    delete_file(TmpFile),
                    fail
                ) )),
        cleanup(( sit_stop_server(PID),
                  ( exists_file(TmpFile) -> delete_file(TmpFile) ; true ) ))
    ]) :-
    %% 1. Root route responds with HTTP 200.
    sit_http_get_status('http://localhost:18182/', RootStatus, RootBody),
    RootStatus =:= 200,
    %% 2. Root route renders an HTML form (menu).
    ( sub_atom(RootBody, _, _, _, 'form') ; sub_atom(RootBody, _, _, _, 'radio') ), !,
    %% 3. POSTing Choice=1 to /step_1 enters the Register flow.
    sit_http_post_form('http://localhost:18182/step_1',
                       ['Choice'='1'], RegStatus, _RegBody),
    ( RegStatus =:= 200 ; RegStatus =:= 302 ),
    %% 4. POSTing Choice=2 to /step_1 enters the Login flow.
    sit_http_post_form('http://localhost:18182/step_1',
                       ['Choice'='2'], LoginStatus, _LoginBody),
    ( LoginStatus =:= 200 ; LoginStatus =:= 302 ),
    %% 5. POSTing Choice=3 to /step_1 enters the Forgot Password flow.
    sit_http_post_form('http://localhost:18182/step_1',
                       ['Choice'='3'], ForgotStatus, _ForgotBody),
    ( ForgotStatus =:= 200 ; ForgotStatus =:= 302 ),
    %% 6. POSTing an invalid choice should redirect or re-render (retry loop).
    sit_http_post_form('http://localhost:18182/step_1',
                       ['Choice'='9'], InvalidStatus, _InvalidBody),
    ( InvalidStatus =:= 302 ; InvalidStatus =:= 200 ).

:- end_tests(live_server_auth_example).


% ==========================================================================
% Tests: multi-step flow continuation structure (static analysis)
% ==========================================================================

:- begin_tests(multi_step_flow_structure).

%% Helper: run the full pipeline on auth_example.pl.
auth_cont_steps(Steps, VN) :-
    sit_input_file('auth_example.pl', File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, main/0, CPs),
    extract_continuations(CPs, VN, main/0, Steps).

%% The auth example produces exactly 8 continuation steps.
test(auth_has_eight_steps) :-
    auth_cont_steps(Steps, _),
    length(Steps, 8).

%% Step 0 is the entry point with no received variables.
test(auth_step0_entry_no_recv_vars) :-
    auth_cont_steps([Step0 | _], _),
    Step0 = cont_step(step_0, [], _, _).

%% Step 1 receives the Choice variable (dispatches on menu).
test(auth_step1_receives_choice) :-
    auth_cont_steps([_, Step1 | _], _),
    Step1 = cont_step(step_1, RecvVars, _, _),
    memberchk('Choice', RecvVars).

%% Register flow (choice=1): step 2 has received Username from step_1's
%% then-arm form and is now showing the Password input.
test(auth_register_step2_form_for_password) :-
    auth_cont_steps(Steps, _),
    nth1(3, Steps, Step2),
    Step2 = cont_step(step_2, RecvVars, _, form_resp(_, 'Password', _, _, password)),
    memberchk('Username', RecvVars).

%% Register flow: step 3 has received Password and Username; asks for Email.
test(auth_register_step3_form_for_email) :-
    auth_cont_steps(Steps, _),
    nth1(4, Steps, Step3),
    Step3 = cont_step(step_3, RecvVars, _, form_resp(_, 'Email', _, _, _)),
    memberchk('Password', RecvVars),
    memberchk('Username', RecvVars).

%% Register flow: step 4 is the result step — has all three variables.
test(auth_register_step4_is_result) :-
    auth_cont_steps(Steps, _),
    nth1(5, Steps, Step4),
    Step4 = cont_step(step_4, RecvVars, _, result_resp(_, _)),
    memberchk('Username', RecvVars),
    memberchk('Password', RecvVars),
    memberchk('Email',    RecvVars).

%% Register flow: a result step receives both Username and Password and Email.
test(auth_register_has_result_step) :-
    auth_cont_steps(Steps, _),
    member(Step, Steps),
    Step = cont_step(_, RecvVars, _, result_resp(_, _)),
    memberchk('Username', RecvVars),
    memberchk('Password', RecvVars),
    memberchk('Email', RecvVars).

%% Login flow: step 5 has received Username and asks for Password.
test(auth_login_step5_form_for_password) :-
    auth_cont_steps(Steps, _),
    nth1(6, Steps, Step5),
    Step5 = cont_step(step_5, RecvVars, _, form_resp(_, 'Password', _, _, password)),
    memberchk('Username', RecvVars).

%% Login flow: step 6 is the result step — has Username and Password.
test(auth_login_step6_is_result) :-
    auth_cont_steps(Steps, _),
    nth1(7, Steps, Step6),
    Step6 = cont_step(step_6, RecvVars, _, result_resp(_, _)),
    memberchk('Username', RecvVars),
    memberchk('Password', RecvVars).

%% Login flow: a result step receives both Username and Password (but not Email).
test(auth_login_has_result_step) :-
    auth_cont_steps(Steps, _),
    member(Step, Steps),
    Step = cont_step(_, RecvVars, _, result_resp(_, _)),
    memberchk('Username', RecvVars),
    memberchk('Password', RecvVars),
    \+ memberchk('Email', RecvVars).

%% Forgot-password flow: step 7 has received Email and is the result step.
test(auth_forgot_password_step7_is_result) :-
    auth_cont_steps(Steps, _),
    nth1(8, Steps, Step7),
    Step7 = cont_step(step_7, RecvVars, _, result_resp(_, _)),
    memberchk('Email', RecvVars).

:- end_tests(multi_step_flow_structure).

% ==========================================================================
% Tests: invalid input loops and menu redisplay (static analysis)
% ==========================================================================

:- begin_tests(invalid_input_loop_structure).

%% The auth example must contain a retry_resp(step_0) in the steps,
%% corresponding to the invalid-choice branch.
test(auth_has_retry_resp) :-
    sit_input_file('auth_example.pl', File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, main/0, CPs),
    extract_continuations(CPs, VN, main/0, Steps),
    member(Step, Steps),
    Step = cont_step(_, _, _, Resp),
    response_has_retry(Resp, step_0).

%% The generated output must include http_redirect (for the retry loop).
test(auth_generated_code_has_redirect, [
        setup(( sit_input_file('auth_example.pl', InFile),
                tmp_file_stream(text, TmpFile, TmpStream),
                close(TmpStream) )),
        cleanup(( exists_file(TmpFile) -> delete_file(TmpFile) ; true ))
    ]) :-
    generate_web_server(InFile, TmpFile),
    open(TmpFile, read, S),
    read_all_lines(S, Lines),
    close(S),
    lines_contain(Lines, 'http_redirect').

%% Helper: a simpler loop-only program has a retry_resp step.
test(simple_retry_loop_structure) :-
    V = _,
    VN = ['Choice' = V],
    Body = norm_conj(
        norm_output(writeln('Enter 1 or 2:')),
        norm_conj(
            norm_read_string(user, "\n", "\r", _, V),
            norm_if_then_else(
                norm_goal(member(V, ["1", "2"])),
                norm_output(writeln(ok)),
                norm_goal(loop)
            )
        )
    ),
    detect_checkpoints(Body, VN, loop/0, CPs),
    extract_continuations(CPs, VN, loop/0, Steps),
    member(Step, Steps),
    Step = cont_step(_, _, _, Resp),
    response_has_retry(Resp, step_0).

%% Menu redisplay: the menu step (step_0) is the target of the retry.
test(retry_targets_step_0) :-
    V = _,
    VN = ['X' = V],
    Body = norm_conj(
        norm_read_string(user, "\n", "\r", _, V),
        norm_goal(retry_me)
    ),
    detect_checkpoints(Body, VN, retry_me/0, CPs),
    extract_continuations(CPs, VN, retry_me/0, Steps),
    member(Step, Steps),
    Step = cont_step(_, _, _, retry_resp(step_0)).

:- end_tests(invalid_input_loop_structure).

% ==========================================================================
% Helpers for the static analysis tests
% ==========================================================================

%% response_has_retry(+Response, +Step) is semidet.
%  True when Response contains a retry_resp(Step) at any nesting level.
response_has_retry(retry_resp(S), S) :- !.
response_has_retry(cond_resp(_, Then, Else), S) :-
    ( response_has_retry(Then, S) -> true
    ; response_has_retry(Else, S)
    ).
response_has_retry(todo_resp(_, Inner), S) :-
    response_has_retry(Inner, S).
response_has_retry(form_resp(_, _, _, _, _), _) :- fail.
response_has_retry(menu_resp(_, _, _, _, _, _), _) :- fail.
response_has_retry(result_resp(_, _), _) :- fail.
