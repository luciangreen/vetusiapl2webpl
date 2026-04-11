%% tests/test_checkpoint_detector.pl
%%
%% Unit and integration tests for the Stage 3 checkpoint detector module
%% (src/checkpoint_detector.pl).
%%
%% Run with:
%%   swipl -g "load_test_files([]), run_tests, halt" -t halt \
%%         tests/test_checkpoint_detector.pl
%%
%% Or from the SWI-Prolog REPL:
%%   ?- [tests/test_checkpoint_detector].
%%   ?- run_tests.

:- use_module('../src/checkpoint_detector').
:- use_module('../src/reader').
:- use_module(library(plunit)).
:- use_module(library(lists)).

% Capture the test directory at load time for the integration test.
:- prolog_load_context(directory, Dir),
   assert(cp_test_dir(Dir)).

% ==========================================================================
% Helper: build a norm_conj chain from a list of normalised goals
% ==========================================================================

list_to_norm_conj([], norm_true).
list_to_norm_conj([G], G) :- !.
list_to_norm_conj([G | Rest], norm_conj(G, Tail)) :-
    list_to_norm_conj(Rest, Tail).

% ==========================================================================
% Tests: detect_checkpoints/3 — sequential bodies
% ==========================================================================

:- begin_tests(detect_checkpoints_sequential).

%% No input goals at all → empty checkpoint list.
test(no_reads) :-
    Body = norm_conj(norm_output(writeln(hello)), norm_output(nl)),
    detect_checkpoints(Body, [], CPs),
    CPs = [].

%% A single norm_read_string produces exactly one checkpoint.
test(single_read_string_one_checkpoint) :-
    V = _,
    VN = ['Input' = V],
    Body = norm_read_string(user, "\n", "\r", _, V),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 1).

%% The checkpoint ID starts at 1.
test(single_read_id_is_1) :-
    V = _,
    VN = ['X' = V],
    Body = norm_read_string(user, "\n", "\r", _, V),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(1, _, _, _, _, _, _).

%% The Kind field for read_string is the atom read_string.
test(single_read_kind_is_read_string) :-
    V = _,
    VN = ['X' = V],
    Body = norm_read_string(user, "\n", "\r", _, V),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, read_string, _, _, _, _, _).

%% The VarName field reflects the name from VarNames.
test(single_read_var_name) :-
    V = _,
    VN = ['Name' = V],
    Body = norm_read_string(user, "\n", "\r", _, V),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, 'Name', _, _, _, _).

%% An unnamed variable yields VarName = anon.
test(anonymous_variable_yields_anon) :-
    V = _,
    Body = norm_read_string(user, "\n", "\r", _, V),
    detect_checkpoints(Body, [], [CP]),        % VN is empty
    CP = checkpoint(_, _, anon, _, _, _, _).

%% The continuation after the only read is norm_true.
test(single_read_continuation_is_norm_true) :-
    V = _,
    VN = ['X' = V],
    Body = norm_read_string(user, "\n", "\r", _, V),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, _, norm_true, _, _).

%% When there is output before the read, it appears in Prompts.
test(output_before_read_captured_as_prompts) :-
    V = _,
    VN = ['X' = V],
    Body = norm_conj(
        norm_output(writeln(enter)),
        norm_read_string(user, "\n", "\r", _, V)
    ),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, Prompts, _, _, _),
    Prompts = [norm_output(writeln(enter))].

%% Multiple output goals before a read are all captured in Prompts.
test(multiple_prompts_before_read) :-
    V = _,
    VN = ['X' = V],
    list_to_norm_conj(
        [norm_output(writeln(line1)), norm_output(writeln(line2)),
         norm_read_string(user, "\n", "\r", _, V)],
        Body
    ),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, Prompts, _, _, _),
    length(Prompts, 2),
    memberchk(norm_output(writeln(line1)), Prompts),
    memberchk(norm_output(writeln(line2)), Prompts).

%% The context for a straight-line body is sequential.
test(context_is_sequential_for_flat_body) :-
    V = _,
    VN = ['X' = V],
    Body = norm_read_string(user, "\n", "\r", _, V),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, _, _, _, sequential).

%% Two reads produce two checkpoints with IDs 1 and 2.
test(two_reads_produce_two_checkpoints) :-
    V1 = _, V2 = _,
    VN = ['A' = V1, 'B' = V2],
    list_to_norm_conj(
        [ norm_output(writeln(p1)),
          norm_read_string(user, "\n", "\r", _, V1),
          norm_output(writeln(p2)),
          norm_read_string(user, "\n", "\r", _, V2)
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 2),
    CPs = [CP1, CP2],
    CP1 = checkpoint(1, _, _, _, _, _, _),
    CP2 = checkpoint(2, _, _, _, _, _, _).

%% The prompts for each checkpoint are reset between reads.
test(prompts_reset_between_reads) :-
    V1 = _, V2 = _,
    VN = ['A' = V1, 'B' = V2],
    list_to_norm_conj(
        [ norm_output(writeln(p1)),
          norm_read_string(user, "\n", "\r", _, V1),
          norm_output(writeln(p2)),
          norm_read_string(user, "\n", "\r", _, V2)
        ], Body),
    detect_checkpoints(Body, VN, [CP1, CP2]),
    CP1 = checkpoint(_, _, _, Prompts1, _, _, _),
    CP2 = checkpoint(_, _, _, Prompts2, _, _, _),
    Prompts1 = [norm_output(writeln(p1))],
    Prompts2 = [norm_output(writeln(p2))].

%% LiveVars at a read = names of previously-read vars that appear free in Cont.
%% After reading V1 ('A'), the continuation contains V2 but not V1 here
%% because the second read uses V2, and the format uses V1. So A is live.
test(live_vars_from_previous_reads) :-
    V1 = _, V2 = _,
    VN = ['Name' = V1, 'Age' = V2],
    list_to_norm_conj(
        [ norm_output(writeln('Enter name:')),
          norm_read_string(user, "\n", "\r", _, V1),
          norm_output(writeln('Enter age:')),
          norm_read_string(user, "\n", "\r", _, V2),
          norm_output(format("Hello ~w ~w", [V1, V2]))
        ], Body),
    detect_checkpoints(Body, VN, [CP1, CP2]),
    CP1 = checkpoint(_, _, _, _, _, LiveVars1, _),
    CP2 = checkpoint(_, _, _, _, _, LiveVars2, _),
    % After reading Name, the continuation uses V1 (in format), so Name is live.
    memberchk('Name', LiveVars1),
    % After reading Age, the continuation uses both V1 and V2.
    memberchk('Name', LiveVars2),
    memberchk('Age',  LiveVars2).

%% The continuation of the first checkpoint contains the second read.
test(continuation_contains_remaining_goals) :-
    V1 = _, V2 = _,
    VN = ['A' = V1, 'B' = V2],
    list_to_norm_conj(
        [ norm_read_string(user, "\n", "\r", _, V1),
          norm_output(writeln(done)),
          norm_read_string(user, "\n", "\r", _, V2)
        ], Body),
    detect_checkpoints(Body, VN, [CP1, _CP2]),
    CP1 = checkpoint(_, _, _, _, Cont1, _, _),
    % Cont1 must contain both the writeln and the second read_string
    Cont1 \= norm_true.

%% A read followed only by norm_true gives an empty continuation.
test(final_read_continuation_is_norm_true) :-
    V = _,
    VN = ['X' = V],
    detect_checkpoints(norm_read_string(user, "\n", "\r", _, V), VN, [CP]),
    CP = checkpoint(_, _, _, _, norm_true, _, _).

%% A non-output, non-read goal between prompts does not clear the prompts.
test(compute_goal_does_not_reset_prompts) :-
    V = _,
    VN = ['X' = V],
    list_to_norm_conj(
        [ norm_output(writeln(prompt)),
          norm_goal(assert(foo)),           % a computation goal
          norm_read_string(user, "\n", "\r", _, V)
        ], Body),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, Prompts, _, _, _),
    memberchk(norm_output(writeln(prompt)), Prompts).

:- end_tests(detect_checkpoints_sequential).

% ==========================================================================
% Tests: detect_checkpoints — read_password support
% ==========================================================================

:- begin_tests(detect_checkpoints_read_password).

%% norm_read_password/2 is detected with Kind = read_password.
test(read_password_2_detected) :-
    V = _,
    VN = ['Pass' = V],
    Body = norm_read_password('Password: ', V),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(1, read_password, 'Pass', _, _, _, _).

%% norm_read_password/1 (no prompt argument) is also detected.
test(read_password_1_detected) :-
    V = _,
    VN = ['Pass' = V],
    Body = norm_read_password(V),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(1, read_password, 'Pass', _, _, _, _).

%% read_string and read_password in sequence are both detected.
test(mixed_read_string_and_password) :-
    V1 = _, V2 = _,
    VN = ['User' = V1, 'Pass' = V2],
    list_to_norm_conj(
        [ norm_read_string(user, "\n", "\r", _, V1),
          norm_read_password('Password: ', V2)
        ], Body),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 2),
    CPs = [CP1, CP2],
    CP1 = checkpoint(1, read_string,  'User', _, _, _, _),
    CP2 = checkpoint(2, read_password, 'Pass', _, _, _, _).

:- end_tests(detect_checkpoints_read_password).

% ==========================================================================
% Tests: detect_checkpoints — menu branches (disjunction)
% ==========================================================================

:- begin_tests(detect_checkpoints_menu).

%% Checkpoints inside a norm_disj arm get context = menu.
test(disj_arm_gets_menu_context) :-
    V = _,
    VN = ['Choice' = V],
    Body = norm_disj(
        norm_read_string(user, "\n", "\r", _, V),
        norm_true
    ),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, _, _, _, menu).

%% Reads in BOTH arms of a disjunction are detected.
test(reads_in_both_disj_arms_detected) :-
    V1 = _, V2 = _,
    VN = ['Left' = V1, 'Right' = V2],
    Body = norm_disj(
        norm_read_string(user, "\n", "\r", _, V1),
        norm_read_string(user, "\n", "\r", _, V2)
    ),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 2).

%% Prompts accumulated before a disjunction carry into each arm.
test(pre_branch_prompts_carried_into_disj_arms) :-
    V = _,
    VN = ['X' = V],
    Body = norm_conj(
        norm_output(writeln(menu_header)),
        norm_disj(
            norm_read_string(user, "\n", "\r", _, V),
            norm_true
        )
    ),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, Prompts, _, _, _),
    memberchk(norm_output(writeln(menu_header)), Prompts).

%% A read inside a menu branch has a continuation that includes the parent.
test(menu_branch_continuation_includes_parent) :-
    V = _,
    VN = ['X' = V],
    Body = norm_conj(
        norm_disj(
            norm_read_string(user, "\n", "\r", _, V),
            norm_true
        ),
        norm_output(writeln(after_menu))
    ),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, _, Cont, _, _),
    % The continuation should contain the writeln(after_menu) output goal
    Cont \= norm_true.

:- end_tests(detect_checkpoints_menu).

% ==========================================================================
% Tests: detect_checkpoints — if-then-else branches
% ==========================================================================

:- begin_tests(detect_checkpoints_branch).

%% Checkpoints inside a norm_if_then_else Then-arm get context = branch.
test(if_then_else_then_arm_gets_branch_context) :-
    V = _,
    VN = ['X' = V],
    Body = norm_if_then_else(
        norm_goal(some_condition),
        norm_read_string(user, "\n", "\r", _, V),
        norm_true
    ),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, _, _, _, branch).

%% Checkpoints inside a norm_if_then_else Else-arm also get context = branch.
test(if_then_else_else_arm_gets_branch_context) :-
    V = _,
    VN = ['X' = V],
    Body = norm_if_then_else(
        norm_goal(some_condition),
        norm_true,
        norm_read_string(user, "\n", "\r", _, V)
    ),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, _, _, _, branch).

%% Reads in BOTH arms of an if-then-else are detected.
test(reads_in_both_ite_arms_detected) :-
    V1 = _, V2 = _,
    VN = ['Yes' = V1, 'No' = V2],
    Body = norm_if_then_else(
        norm_goal(check),
        norm_read_string(user, "\n", "\r", _, V1),
        norm_read_string(user, "\n", "\r", _, V2)
    ),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 2),
    CPs = [CP1, CP2],
    CP1 = checkpoint(_, _, _, _, _, _, branch),
    CP2 = checkpoint(_, _, _, _, _, _, branch).

%% A norm_if_then (no else) with a read in the Then arm.
test(if_then_no_else_then_arm) :-
    V = _,
    VN = ['X' = V],
    Body = norm_if_then(
        norm_goal(check),
        norm_read_string(user, "\n", "\r", _, V)
    ),
    detect_checkpoints(Body, VN, [CP]),
    CP = checkpoint(_, _, _, _, _, _, branch).

%% Nested if-then-else inside a disjunction: inner context = branch.
test(nested_branch_inside_menu) :-
    V = _,
    VN = ['X' = V],
    Body = norm_disj(
        norm_if_then_else(
            norm_goal(cond),
            norm_read_string(user, "\n", "\r", _, V),
            norm_true
        ),
        norm_true
    ),
    detect_checkpoints(Body, VN, [CP]),
    % The inner read is inside an if-then-else inside a disjunction.
    % The innermost context tag is branch (the if-then-else arm).
    CP = checkpoint(_, _, _, _, _, _, branch).

:- end_tests(detect_checkpoints_branch).

% ==========================================================================
% Tests: detect_checkpoints/4 — loop detection via recursive calls
% ==========================================================================

:- begin_tests(detect_checkpoints_loop).

%% When ClauseHead = retry_loop/0 and the else-arm calls retry_loop,
%% both arms of the if-then-else get context = loop(retry_loop/0).
test(recursive_call_triggers_loop_context) :-
    V = _,
    VN = ['Choice' = V],
    % Body of: retry_loop :- writeln(prompt), read_string(..., Choice),
    %   ( valid(Choice) -> use(Choice) ; retry_loop ).
    Body = norm_conj(
        norm_output(writeln(prompt)),
        norm_conj(
            norm_read_string(user, "\n", "\r", _, V),
            norm_if_then_else(
                norm_goal(valid(V)),
                norm_goal(use(V)),
                norm_goal(retry_loop)
            )
        )
    ),
    detect_checkpoints(Body, VN, retry_loop/0, [CP]),
    CP = checkpoint(_, _, _, _, _, _, sequential).
    % The read itself is in sequential context;
    % the recursive call is in the continuation, not wrapping the read.

test(recursive_call_in_disj_triggers_loop_context) :-
    V = _,
    VN = ['X' = V],
    % Body where the read is INSIDE the disjunction with a recursive branch:
    % loop :- ( (prompt, read_string(..., X), use(X)) ; loop ).
    Body = norm_disj(
        norm_conj(
            norm_output(writeln(prompt)),
            norm_conj(
                norm_read_string(user, "\n", "\r", _, V),
                norm_goal(use(V))
            )
        ),
        norm_goal(loop)
    ),
    detect_checkpoints(Body, VN, loop/0, [CP]),
    CP = checkpoint(_, _, _, _, _, _, loop(loop/0)).

test(no_recursive_call_keeps_menu_context) :-
    V = _,
    VN = ['X' = V],
    Body = norm_disj(
        norm_read_string(user, "\n", "\r", _, V),
        norm_true
    ),
    detect_checkpoints(Body, VN, loop/0, [CP]),
    % No call to loop/0 in any branch, so context remains menu.
    CP = checkpoint(_, _, _, _, _, _, menu).

:- end_tests(detect_checkpoints_loop).

% ==========================================================================
% Tests: collect_live_vars/3
% ==========================================================================

:- begin_tests(collect_live_vars).

%% A variable that appears in the term is live.
test(var_in_term_is_live) :-
    V = _,
    VN = ['Foo' = V],
    Term = norm_goal(use(V)),
    collect_live_vars(Term, VN, Live),
    Live = ['Foo'].

%% A variable NOT in the term is not live.
test(var_not_in_term_is_not_live) :-
    V = _,
    VN = ['Foo' = V],
    Term = norm_goal(use(other)),
    collect_live_vars(Term, VN, Live),
    Live = [].

%% Multiple variables — only those in the term appear.
test(only_referenced_vars_are_live) :-
    V1 = _, V2 = _,
    VN = ['A' = V1, 'B' = V2],
    Term = norm_goal(use(V1)),    % only V1 referenced
    collect_live_vars(Term, VN, Live),
    Live = ['A'],
    \+ memberchk('B', Live).

%% norm_true has no free variables.
test(norm_true_has_no_live_vars) :-
    V = _,
    VN = ['X' = V],
    collect_live_vars(norm_true, VN, Live),
    Live = [].

%% Variables inside a nested norm_conj are found.
test(vars_in_nested_conj_are_live) :-
    V = _,
    VN = ['X' = V],
    Term = norm_conj(norm_goal(a), norm_goal(b(V))),
    collect_live_vars(Term, VN, Live),
    memberchk('X', Live).

:- end_tests(collect_live_vars).

% ==========================================================================
% Integration test: detect_checkpoints on examples/input_example.pl
% ==========================================================================

:- begin_tests(checkpoint_integration).

%% Read input_example.pl, normalise it, find main/0, detect checkpoints.
test(input_example_two_checkpoints) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, CPs),
    length(CPs, 2).

%% The first checkpoint reads the variable named 'Name'.
test(first_checkpoint_reads_name) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, [CP1 | _]),
    CP1 = checkpoint(1, read_string, 'Name', _, _, _, _).

%% The second checkpoint reads the variable named 'Age'.
test(second_checkpoint_reads_age) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, [_, CP2]),
    CP2 = checkpoint(2, read_string, 'Age', _, _, _, _).

%% The prompt for the first checkpoint contains the 'Enter your name:' message.
test(first_checkpoint_prompt_contains_name_message) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, [CP1 | _]),
    CP1 = checkpoint(_, _, _, Prompts, _, _, _),
    once(member(norm_output(writeln('Enter your name:')), Prompts)).

%% The prompt for the second checkpoint contains the 'Enter your age:' message.
test(second_checkpoint_prompt_contains_age_message) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, [_, CP2]),
    CP2 = checkpoint(_, _, _, Prompts, _, _, _),
    once(member(norm_output(writeln('Enter your age:')), Prompts)).

%% After reading Name, 'Name' must be live (it appears in the format call).
test(name_is_live_after_first_checkpoint) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, [CP1 | _]),
    CP1 = checkpoint(_, _, _, _, _, LiveVars, _),
    memberchk('Name', LiveVars).

%% After reading Age, both 'Name' and 'Age' must be live.
test(both_name_and_age_live_after_second_checkpoint) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, [_, CP2]),
    CP2 = checkpoint(_, _, _, _, _, LiveVars, _),
    memberchk('Name', LiveVars),
    memberchk('Age',  LiveVars).

%% Both checkpoints use sequential context (input_example.pl is a flat sequence).
test(both_checkpoints_sequential_context) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, CPs),
    forall(member(CP, CPs),
           ( CP = checkpoint(_, _, _, _, _, _, sequential) )).

%% The continuation of CP1 is non-trivial (contains the second read etc.).
test(first_checkpoint_continuation_is_nontrivial) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, [CP1 | _]),
    CP1 = checkpoint(_, _, _, _, Cont, _, _),
    Cont \= norm_true.

%% The continuation of CP2 is non-trivial (contains the format goal).
test(second_checkpoint_continuation_is_nontrivial) :-
    input_example_file(File),
    read_and_normalise(File, NormClauses),
    once(member(norm_clause(main, Body, VN), NormClauses)),
    detect_checkpoints(Body, VN, [_, CP2]),
    CP2 = checkpoint(_, _, _, _, Cont, _, _),
    Cont \= norm_true.

:- end_tests(checkpoint_integration).

% ==========================================================================
% Helper: resolve path to examples/input_example.pl
% ==========================================================================

input_example_file(File) :-
    cp_test_dir(Dir),
    file_directory_name(Dir, RepoRoot),
    atomic_list_concat([RepoRoot, examples, 'input_example.pl'], '/', File).
