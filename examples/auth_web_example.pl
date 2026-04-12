%% examples/auth_web_example.pl
%%
%%  Hand-annotated reference output produced by the vetusiapl2webpl converter
%%  from examples/auth_example.pl (Stage 13 — Example-Based Conversion).
%%
%%  Input program:  examples/auth_example.pl
%%    A terminal authentication menu with three flows:
%%      1. Register  — collects Username, Password, Email
%%      2. Login     — collects Username, Password
%%      3. Forgot Password — collects Email only
%%    An invalid menu choice redirects back to the landing page (retry loop).
%%
%%  To regenerate automatically:
%%
%%    swipl -q -g main -s src/vetusia_converter.pl -- \
%%          examples/auth_example.pl -o output/auth_web.pl
%%
%%  To run:
%%    swipl examples/auth_web_example.pl
%%  Then open http://localhost:8080 in your browser.
%%
%%  Generated handler summary
%%  -------------------------
%%    step_0  GET  /           — landing page: authentication menu (radio buttons)
%%    step_1  POST /step_1     — dispatch on Choice: branch to register, login,
%%                               forgot-password, or redirect to step_0
%%    step_2  POST /step_2     — register: receive Username, collect Password
%%    step_3  POST /step_3     — register: receive Username+Password, collect Email
%%    step_4  POST /step_4     — register: receive all three, show result
%%    step_5  POST /step_5     — login: receive Username, collect Password
%%    step_6  POST /step_6     — login: receive Username+Password, show result
%%    step_7  POST /step_7     — forgot: receive Email, show result

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_header)).

%% --------------------------------------------------
%% Runtime helpers loaded from web_support.pl (Stage 11)
%% --------------------------------------------------
%%
%% The converter normally inlines these helpers (via emit_html_helpers/1 from
%% html_output.pl and emit_state_serialiser_helpers/1 from state_serialiser.pl),
%% making each generated file self-contained.  This reference example uses
%% use_module(web_support) for brevity; the two forms are equivalent at runtime.

:- use_module(web_support).

%% --------------------------------------------------
%% HTTP handler declarations
%% --------------------------------------------------

:- http_handler(root(.), step_0, []).
:- http_handler(root(step_1), step_1, [method(post)]).
:- http_handler(root(step_2), step_2, [method(post)]).
:- http_handler(root(step_3), step_3, [method(post)]).
:- http_handler(root(step_4), step_4, [method(post)]).
:- http_handler(root(step_5), step_5, [method(post)]).
:- http_handler(root(step_6), step_6, [method(post)]).
:- http_handler(root(step_7), step_7, [method(post)]).

vetusia_server(Port) :-
    http_server(http_dispatch, [port(Port)]).

:- initialization(main, main).

main :-
    vetusia_server(8080).

%% --------------------------------------------------
%% step_0 — root GET handler: authentication system landing page.
%%
%%  Displays the full menu as a set of radio buttons (3 choices → radio,
%%  per Stage 9 menu_input_kind/2 rule: ≤4 choices → radio).
%%  Prompts from the original main/0 body (before the read_string) become
%%  HTML <p> elements above the radio widget.
%%  Posts to /step_1.
%% --------------------------------------------------

step_0(_Request) :-
    reply_html_page(
        title('Form'),
        [ form([method=post, action='/step_1'],
              [ p('=== Authentication System ==='),
                p('1. Register'),
                p('2. Login'),
                p('3. Forgot Password'),
                p('Enter choice (1/2/3):'),
                span([], [ input([type=radio, name='Choice', value="1"]),
                           '1. Register' ]),
                span([], [ input([type=radio, name='Choice', value="2"]),
                           '2. Login' ]),
                span([], [ input([type=radio, name='Choice', value="3"]),
                           '3. Forgot Password' ]),
                input([type=submit, value='Next'])
              ])
        ]).

%% --------------------------------------------------
%% step_1 — POST: receive Choice, branch to the correct flow.
%%
%%  Choice is received as a raw atom (Choice_raw) via http_parameters/2 and
%%  then restored to its original Prolog term via state_deserialise/2.
%%
%%  The if-then-else mirrors the original terminal program's branching.
%%  Each branch shows the flow-specific prompts and collects the first
%%  variable of that flow; there are no hidden fields because the branch
%%  variables (Username / Email) are the only live variables in their
%%  respective continuations — Choice is not referenced downstream.
%%
%%  The invalid-choice else arm uses http_redirect to send the user back
%%  to step_0 (the web equivalent of the original recursive main call).
%% --------------------------------------------------

step_1(Request) :-
    http_parameters(Request,
        [ 'Choice'(Choice_raw, [atom])
        ]),
    state_deserialise(Choice_raw, Choice),
    (   Choice = "1"
    ->  reply_html_page(
            title('Form'),
            [ form([method=post, action='/step_2'],
                  [ p('-- Register --'),
                    p('Enter username:'),
                    input([type=text, name='Username', autofocus=autofocus]),
                    input([type=submit, value='Next'])
                  ]) ])
    ;   Choice = "2"
    ->  reply_html_page(
            title('Form'),
            [ form([method=post, action='/step_5'],
                  [ p('-- Login --'),
                    p('Enter username:'),
                    input([type=text, name='Username', autofocus=autofocus]),
                    input([type=submit, value='Next'])
                  ]) ])
    ;   Choice = "3"
    ->  reply_html_page(
            title('Form'),
            [ form([method=post, action='/step_7'],
                  [ p('-- Forgot Password --'),
                    p('Enter your email:'),
                    input([type=text, name='Email', autofocus=autofocus]),
                    input([type=submit, value='Next'])
                  ]) ])
    ;   http_redirect(see_other, root(.), Request)
    ).

%% --------------------------------------------------
%% Register flow: steps 2, 3, 4
%% --------------------------------------------------

%% step_2 — POST: receive Username, collect Password.
%%
%%  Username is live in the continuation (it appears in the final format/2
%%  call), so it is carried forward as a serialised hidden field (Username_s).
%%  The Password field uses input type=password because the variable name
%%  'Password' triggers the Stage 7 password-semantic detector.
%% --------------------------------------------------

step_2(Request) :-
    http_parameters(Request,
        [ 'Username'(Username_raw, [atom])
        ]),
    state_deserialise(Username_raw, Username),
    state_serialise(Username, Username_s),
    reply_html_page(
        title('Form'),
        [ form([method=post, action='/step_3'],
              [ input([type=hidden, name='Username', value=Username_s]),
                p('Enter password:'),
                input([type=password, name='Password', autofocus=autofocus]),
                input([type=submit, value='Next'])
              ]) ]).

%% step_3 — POST: receive Username + Password, collect Email.
%%
%%  Both Username and Password appear in the final format/2 result call, so
%%  both are serialised and carried forward as hidden fields.
%% --------------------------------------------------

step_3(Request) :-
    http_parameters(Request,
        [ 'Password'(Password_raw, [atom]),
          'Username'(Username_raw, [atom])
        ]),
    state_deserialise(Password_raw, Password),
    state_deserialise(Username_raw, Username),
    state_serialise(Password, Password_s),
    state_serialise(Username, Username_s),
    reply_html_page(
        title('Form'),
        [ form([method=post, action='/step_4'],
              [ input([type=hidden, name='Password', value=Password_s]),
                input([type=hidden, name='Username', value=Username_s]),
                p('Enter email:'),
                input([type=text, name='Email', autofocus=autofocus]),
                input([type=submit, value='Next'])
              ]) ]).

%% step_4 — POST: receive Email + Password + Username, show registration result.
%% --------------------------------------------------

step_4(Request) :-
    http_parameters(Request,
        [ 'Email'(Email_raw, [atom]),
          'Password'(Password_raw, [atom]),
          'Username'(Username_raw, [atom])
        ]),
    state_deserialise(Email_raw, Email),
    state_deserialise(Password_raw, Password),
    state_deserialise(Username_raw, Username),
    html_page_header('Result'),
    format("Registered: ~w / ~w (email: ~w)~n", [Username, Password, Email]),
    html_page_footer.

%% --------------------------------------------------
%% Login flow: steps 5, 6
%% --------------------------------------------------

%% step_5 — POST: receive Username (login branch), collect Password.
%% --------------------------------------------------

step_5(Request) :-
    http_parameters(Request,
        [ 'Username'(Username_raw, [atom])
        ]),
    state_deserialise(Username_raw, Username),
    state_serialise(Username, Username_s),
    reply_html_page(
        title('Form'),
        [ form([method=post, action='/step_6'],
              [ input([type=hidden, name='Username', value=Username_s]),
                p('Enter password:'),
                input([type=password, name='Password', autofocus=autofocus]),
                input([type=submit, value='Next'])
              ]) ]).

%% step_6 — POST: receive Username + Password, show login result.
%% --------------------------------------------------

step_6(Request) :-
    http_parameters(Request,
        [ 'Password'(Password_raw, [atom]),
          'Username'(Username_raw, [atom])
        ]),
    state_deserialise(Password_raw, Password),
    state_deserialise(Username_raw, Username),
    html_page_header('Result'),
    format("Welcome back, ~w! (pass: ~w)~n", [Username, Password]),
    html_page_footer.

%% --------------------------------------------------
%% Forgot Password flow: step 7
%% --------------------------------------------------

%% step_7 — POST: receive Email (forgot-password branch), show result.
%% --------------------------------------------------

step_7(Request) :-
    http_parameters(Request,
        [ 'Email'(Email_raw, [atom])
        ]),
    state_deserialise(Email_raw, Email),
    html_page_header('Result'),
    format("Password reset link sent to: ~w~n", [Email]),
    html_page_footer.
