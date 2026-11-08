%% tests/test_funnel_example.pl
%%
%% A funnel-shaped program (examples/funnel_example.pl) converted and run:
%%   - raw HTML lines reach the page unescaped inside reply_html_page/2,
%%   - goals before the first prompt run when the landing page is opened,
%%   - every tested menu choice becomes a radio button,
%%   - typed fields come back as strings, as read_string/5 gives them, so
%%     Choice = "1" matches and a typed "Ann" is not parsed as a variable,
%%   - hidden fields still round-trip through state_serialise/2.
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt tests/test_funnel_example.pl

:- use_module('../src/web_server_generator').
:- use_module('../src/html_output').
:- use_module(library(plunit)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(http/http_open)).

:- prolog_load_context(directory, Dir), assert(tfe_dir(Dir)).

tfe_example(File) :-
    tfe_dir(Dir), file_directory_name(Dir, Root),
    atomic_list_concat([Root, '/examples/funnel_example.pl'], File).

tfe_generate(Dir, Port, Code) :-
    tfe_example(In),
    tmp_file(funnel, Dir), make_directory(Dir),
    atomic_list_concat([Dir, '/funnel_web.pl'], Out),
    generate_web_server(In, Out, Port),
    read_file_to_string(Out, Code, []).

tfe_get(URL, Body) :-
    http_open(URL, In, [status_code(200)]), read_string(In, _, Body), close(In).
tfe_post(URL, Pairs, Body) :-
    http_open(URL, In, [method(post), post(form(Pairs)), status_code(200)]),
    read_string(In, _, Body), close(In).

tfe_wait(_, 0) :- !, fail.
tfe_wait(Port, N) :-
    format(atom(URL), 'http://localhost:~w/', [Port]),
    (   catch((http_open(URL, In, [status_code(_)]), close(In)), _, fail)
    ->  true
    ;   sleep(0.2), N1 is N - 1, tfe_wait(Port, N1)
    ).

has(Text, Sub) :- sub_string(Text, _, _, _, Sub), !.

:- begin_tests(funnel_example_conversion).

test(raw_html_term) :-
    norm_output_to_html_term(norm_output(writeln('<h1>Hi</h1>')), T),
    T == \['<h1>Hi</h1>'].

test(format_term_uses_helper) :-
    norm_output_to_html_term(norm_output(format('~w!', [x])), T),
    T == \html_format('~w!', [x]).

test(generated_handlers) :-
    tfe_generate(_Dir, 18191, Code),
    assertion(\+ has(Code, "\\format(")),
    assertion(has(Code, "html_format(Fmt, Args) -->")),
    % the visit is recorded when the landing page is requested
    assertion(has(Code, "landing_pad_main(_Request):-record(visit)")),
    % typed fields are strings; the hidden Name is deserialised
    assertion(has(Code, "atom_string(Name_raw,Name)")),
    assertion(has(Code, "atom_string(Choice_raw,Choice)")),
    assertion(has(Code, "state_deserialise(Name_raw,Name)")),
    % both tested choices are offered
    assertion(has(Code, "value=\"1\"")),
    assertion(has(Code, "value=\"2\"")).

:- end_tests(funnel_example_conversion).

:- begin_tests(funnel_example_live).

test(walk_the_funnel) :-
    Port = 18192,
    tfe_generate(Dir, Port, _),
    current_prolog_flag(executable, Swipl),
    format(atom(Goal), 'vetusia_server(~w), thread_get_message(_)', [Port]),
    process_create(Swipl, ['-q', '-g', Goal, '-s', 'funnel_web.pl'],
                   [cwd(Dir), process(PID), stdout(null), stderr(null)]),
    format(atom(Root), 'http://localhost:~w/', [Port]),
    call_cleanup(
        (   assertion(tfe_wait(Port, 50)),
            tfe_get(Root, Page0),
            assertion(has(Page0, "<h1>Welcome</h1>")),
            atom_concat(Root, resume_main_1, U1),
            tfe_post(U1, ['Name'='Ann'], Page1),
            assertion(has(Page1, "1. Yes please")),
            assertion(has(Page1, "value=\"2\"")),
            atom_concat(Root, resume_main_2, U2),
            tfe_post(U2, ['Choice'='1', 'Name'='"Ann"'], Page2),
            assertion(has(Page2, "<p>You chose yes.</p>")),
            tfe_post(U1, ['Name'='Ben'], _),
            tfe_post(U2, ['Choice'='2', 'Name'='"Ben"'], Page3),
            assertion(has(Page3, "<p>You chose no.</p>"))
        ),
        ( catch(process_kill(PID), _, true), catch(process_wait(PID, _), _, true) )),
    atomic_list_concat([Dir, '/funnel_events.pl'], Events),
    read_file_to_terms(Events, Terms, []),
    % one visit per landing-page request (the readiness check above is one too)
    exclude(==(visit), Terms, Choices),
    assertion(Choices == [yes("Ann"), no("Ben")]),
    assertion(memberchk(visit, Terms)).

:- end_tests(funnel_example_live).
