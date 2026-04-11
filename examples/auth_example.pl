%% examples/auth_example.pl
%
%  A multi-step terminal authentication program with three flows:
%    1. Register  — collects username, password, and email
%    2. Login     — collects username and password
%    3. Forgot Password — collects email address only
%  An invalid menu choice causes the menu to redisplay (retry loop).
%
%  This file is used as input to the vetusiapl2webpl converter and as the
%  integration-test fixture for the Stage 4 continuation extractor.
%
%  Run the converter with:
%
%    swipl -g "use_module('src/vetusiapl2webpl'), \
%               convert('examples/auth_example.pl', \
%                       'output/auth_web.pl'), halt" -t halt

:- initialization(main, main).

main :-
    writeln('=== Authentication System ==='),
    writeln('1. Register'),
    writeln('2. Login'),
    writeln('3. Forgot Password'),
    writeln('Enter choice (1/2/3):'),
    read_string(user, "\n", "\r", _, Choice),
    ( Choice = "1" ->
        writeln('-- Register --'),
        writeln('Enter username:'),
        read_string(user, "\n", "\r", _, Username),
        writeln('Enter password:'),
        read_string(user, "\n", "\r", _, Password),
        writeln('Enter email:'),
        read_string(user, "\n", "\r", _, Email),
        format("Registered: ~w / ~w (email: ~w)~n", [Username, Password, Email])
    ; Choice = "2" ->
        writeln('-- Login --'),
        writeln('Enter username:'),
        read_string(user, "\n", "\r", _, Username),
        writeln('Enter password:'),
        read_string(user, "\n", "\r", _, Password),
        format("Welcome back, ~w! (pass: ~w)~n", [Username, Password])
    ; Choice = "3" ->
        writeln('-- Forgot Password --'),
        writeln('Enter your email:'),
        read_string(user, "\n", "\r", _, Email),
        format("Password reset link sent to: ~w~n", [Email])
    ;
        writeln('Invalid choice. Please try again.'),
        main
    ).
