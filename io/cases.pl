% The predicates whose inputs and outputs are recorded in io/ios.txt (see io/ios_engine.pl).
:- ios_engine:load_repo('src/html_output').
:- ios_engine:load_repo('src/state_serialiser').
:- ios_engine:load_repo('src/reader').
:- ios_engine:load_repo('src/form_generator').
:- ios_engine:load_repo('src/menu_recogniser').
:- ios_engine:load_repo('src/vetusiapl2webpl').
:- use_module(library(readutil)).

io_title('vetusiapl2webpl').

io_cases([looks_like_html, html_escape, state_round_trip, normalise_body, is_output_goal,
          select_input_type, menu_input_kind, convert]).

texts(['<p>Hello</p>', 'Enter your name:', '42', '', 'a < b', 'Hello <b>World</b>!', '<br/>',
       'Price: $5 & tax', '<script>x</script>', 'Tom & "Jerry"', '<h1>Title</h1> and more', 'x > y']).
values([hello, 42, -7, 3.14, "a string", [1, 2, 3], f(x, [y]), 'Hello World', [], "", point(1, 2), 'it''s']).
bodies([true, !, (a, b), (a ; b), (a -> b), (a -> b ; c), (writeln(x), nl), \+ a,
        (read_string(user_input, "\n", "\r", _, S), writeln(S)), (X = 1, Y is X + 1, write(Y)), format("~w~n", [z]), (a, (b ; c))]).
goals([writeln(x), write(y), nl, format("~w", [a]), format(hi), writef('%w', [b]), print(z), read(x), atom_length(a, _), true]).
varnames(['Name', 'Password', 'Comment', 'Age', 'Message', 'Pin', 'Notes', 'City', 'Secret', 'Description']).
prompts([["Enter your name:"], ["Please describe the problem in detail:"], ["Choice?"], [], ["Write a long message:"], ["Password:"]]).

% Small terminal programs that read input, made from parts.
program(K, Text) :-
    pick(K, 1, ["name", "city", "colour", "food"], Thing),
    pick(K, 2, ["Hello, ", "You chose ", "Thanks: "], Reply),
    num(K, 3, 1, 3, Kind),
    ( Kind =:= 1
    -> format(string(Text), "main :-~n    writeln(\"What is your ~w?\"),~n    read_string(user_input, \"\\n\", \"\\r\", _, S),~n    string_concat(\"~w\", S, R),~n    writeln(R).~n", [Thing, Reply])
    ; Kind =:= 2
    -> format(string(Text), "main :-~n    writeln(\"1. Add\"), writeln(\"2. Quit\"),~n    read_string(user_input, \"\\n\", \"\\r\", _, C),~n    ( C = \"1\" -> writeln(\"Added\") ; C = \"2\" -> writeln(\"Bye\") ; writeln(\"Pardon?\") ).~n", [])
    ;  format(string(Text), "main :-~n    writeln(\"Your ~w?\"),~n    read_string(user_input, \"\\n\", \"\\r\", _, A),~n    writeln(\"And another?\"),~n    read_string(user_input, \"\\n\", \"\\r\", _, B),~n    format(\"~~w and ~~w~~n\", [A, B]).~n", [Thing]) ).

io_input(looks_like_html, K, [T]) :- texts(Ts), pick(K, 1, Ts, T).
io_input(html_escape, K, [T]) :- texts(Ts), pick(K, 2, Ts, T).
io_input(state_round_trip, K, [V]) :- values(Vs), pick(K, 3, Vs, V).
io_input(normalise_body, K, [B]) :- bodies(Bs), pick(K, 4, Bs, B).
io_input(is_output_goal, K, [G]) :- goals(Gs), pick(K, 5, Gs, G).
io_input(select_input_type, K, [Read, Var, Prompts]) :- pick(K, 6, [read_string, read_password, read_term], Read), varnames(Vs), pick(K, 7, Vs, Var), prompts(Ps), pick(K, 8, Ps, Prompts).
io_input(menu_input_kind, K, [Choices]) :- num(K, 9, 0, 8, N), ( N =:= 0 -> Choices = [] ; numlist(1, N, Is), maplist([I, menu_choice(V, x)]>>format(string(V), "~d", [I]), Is, Choices) ).
io_input(convert, K, [Program]) :- program(K, Program).

io_run(looks_like_html, [T], yes) :- looks_like_html(T).
io_run(html_escape, [T], E) :- html_escape(T, E).
io_run(state_round_trip, [V], [serialised(A), back(B)]) :- state_serialise(V, A), state_deserialise(A, B).
io_run(normalise_body, [B], N) :- reader:normalise_body(B, N).
io_run(is_output_goal, [G], yes) :- is_output_goal(G).
io_run(select_input_type, [Read, Var, Prompts], T) :- select_input_type(Read, Var, Prompts, T).
io_run(menu_input_kind, [Choices], Kind) :- menu_input_kind(Choices, Kind).
% converts a program and reports the shape of the web program it makes
io_run(convert, [Program], [lines(L), forms(F), predicates(Ps)]) :-
    In = '/tmp/vetusia_ios_in.pl', Out = '/tmp/vetusia_ios_out.pl',
    setup_call_cleanup(open(In, write, S), write(S, Program), close(S)),
    with_output_to(string(_), convert(In, Out)),
    read_file_to_string(Out, Text, []),
    split_string(Text, "\n", "", Lines), length(Lines, L),
    aggregate_all(count, ( sub_string(Text, _, _, _, "<form") ; sub_string(Text, _, _, _, "form(") ), F),
    setup_call_cleanup(open(Out, read, R), heads(R, Hs), close(R)),
    sort(Hs, Ps).

heads(R, Hs) :-
    catch(read_term(R, T, [syntax_errors(quiet)]), _, T = skip),
    ( T == end_of_file -> Hs = []
    ; ( T = (H :- _) -> true ; T = (:- _) -> H = none ; H = T ),
      ( H == none -> Hs = Rest ; callable(H) -> functor(H, N, A), Hs = [N/A | Rest] ; Hs = Rest ),
      heads(R, Rest) ).
