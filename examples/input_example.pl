%% examples/input_example.pl
%
%  A simple terminal Prolog program that asks the user for their name
%  and age, then greets them.
%
%  This file is the INPUT to the vetusiapl2webpl converter.
%  Run the converter with:
%
%    swipl -g "use_module('src/vetusiapl2webpl'), \
%               convert('examples/input_example.pl', \
%                       'output/web_example.pl'), halt" -t halt

:- initialization(main, main).

main :-
    writeln('Enter your name:'),
    read_string(user, "\n", "\r", _, Name),
    writeln('Enter your age:'),
    read_string(user, "\n", "\r", _, Age),
    format("Hello, ~w! You are ~w years old.~n", [Name, Age]).
