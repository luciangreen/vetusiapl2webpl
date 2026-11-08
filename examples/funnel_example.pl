% A small sales funnel: a step before the first prompt (recording the visit),
% raw HTML output, a text field, and a numbered menu tested choice by choice.
:- initialization(main, main).

main :-
    record(visit),
    writeln('<h1>Welcome</h1>'),
    writeln('Your name:'),
    read_string(user, "\n", "\r", _, Name),
    writeln('1. Yes please'),
    writeln('2. No thanks'),
    writeln('Choose 1 or 2:'),
    read_string(user, "\n", "\r", _, Choice),
    (   Choice = "1"
    ->  record(yes(Name)),
        writeln('<p>You chose yes.</p>')
    ;   Choice = "2"
    ->  record(no(Name)),
        writeln('<p>You chose no.</p>')
    ;   writeln('Please choose 1 or 2.')
    ).

record(Event) :-
    setup_call_cleanup(open('funnel_events.pl', append, S),
                       format(S, "~q.~n", [Event]),
                       close(S)).
