:- module(form_generator, [
    select_input_type/4,
    build_hidden_inputs/3,
    build_input_field/3,
    generate_form/7
]).

/** <module> form_generator — Stage 7: HTML Form Generation for read_string

 * Converts a form_resp/5 response description into an HTML form term
 * suitable for use with SWI-Prolog's reply_html_page/2.
 *
 * Responsibilities
 * ----------------
 *   1. **Input-type selection** (select_input_type/4):
 *      Chooses among text, password, and textarea based on the checkpoint
 *      kind (read_string vs read_password) and semantic hints from the
 *      variable name and prompt text.
 *
 *   2. **Hidden state carrier** (build_hidden_inputs/3):
 *      Generates input([type=hidden, …]) terms for every accumulated
 *      variable that must survive the HTTP round-trip to the next step.
 *
 *   3. **Input field builder** (build_input_field/3):
 *      Produces the concrete HTML element for the user-visible input,
 *      including autofocus on the first (and only) interactive field.
 *
 *   4. **Form assembler** (generate_form/7):
 *      Combines hidden fields, prompt HTML, the user input field, and a
 *      submit button into a complete form([method=post, action=…], …) term.
 *
 * Input types
 * -----------
 *   text      — default; used when no stronger signal is present
 *   password  — used when Kind = read_password, or when the variable name
 *               contains "password", "passwd", "secret", or "pin"
 *   textarea  — used when the variable name or prompt text contains a
 *               keyword suggesting long-form input (description, message,
 *               comment, note, bio, about, body, content, feedback, or
 *               prompt phrases like "describe", "your message", etc.)
 *
 * Autofocus
 * ---------
 *   Every user-visible input field (text, password, textarea) carries the
 *   autofocus=autofocus attribute so that the browser places focus on the
 *   field when the page loads.
 *
 * Usage (from continuation_extractor)
 * -------------------------------------
 *   :- use_module('src/form_generator').
 *   ?- select_input_type(read_password, 'Pass', [], InputType).
 *   InputType = password.
 *
 *   ?- generate_form([norm_output(writeln('Enter name:'))],
 *                    'Name', [], step_1, text, [], Form).
 *
 * @author  Lucian Green
 * @license BSD-3-Clause
 */

:- use_module(library(lists)).
:- use_module(html_output).

% ==========================================================================
% Input-type selection
% ==========================================================================

%% select_input_type(+Kind, +VarName, +Prompts, -InputType) is det.
%
%  Choose the HTML input type for a checkpoint based on:
%    1. Kind: read_password always yields password.
%    2. VarName: atoms containing "password", "passwd", "secret", or "pin"
%       yield password even when Kind is read_string.
%    3. VarName or prompt text containing long-form keywords yields textarea.
%    4. Default: text.
%
%  Kind     — read_string | read_password
%  VarName  — atom name of the variable captured by the read goal
%  Prompts  — list of norm_output/1 goals accumulated before this checkpoint
%  InputType — text | password | textarea
select_input_type(read_password, _, _, password) :- !.
select_input_type(read_string, VarName, _, password) :-
    fg_suggests_password(VarName), !.
select_input_type(read_string, VarName, Prompts, textarea) :-
    ( fg_suggests_textarea_name(VarName) -> true
    ; fg_suggests_textarea_prompts(Prompts)
    ), !.
select_input_type(_, _, _, text).

%% fg_suggests_password(+VarName:atom) is semidet.
%
%  True when VarName (case-insensitively) contains a password-like substring.
fg_suggests_password(Name) :-
    downcase_atom(Name, Lower),
    ( sub_atom(Lower, _, _, _, password) -> true
    ; sub_atom(Lower, _, _, _, passwd)   -> true
    ; sub_atom(Lower, _, _, _, secret)   -> true
    ; sub_atom(Lower, _, _, _, pin)      -> true
    ).

%% fg_suggests_textarea_name(+VarName:atom) is semidet.
%
%  True when VarName (case-insensitively) suggests long-form text input.
fg_suggests_textarea_name(Name) :-
    downcase_atom(Name, Lower),
    ( sub_atom(Lower, _, _, _, description) -> true
    ; sub_atom(Lower, _, _, _, message)     -> true
    ; sub_atom(Lower, _, _, _, comment)     -> true
    ; sub_atom(Lower, _, _, _, note)        -> true
    ; sub_atom(Lower, _, _, _, bio)         -> true
    ; sub_atom(Lower, _, _, _, about)       -> true
    ; sub_atom(Lower, _, _, _, body)        -> true
    ; sub_atom(Lower, _, _, _, content)     -> true
    ; sub_atom(Lower, _, _, _, feedback)    -> true
    ).

%% fg_suggests_textarea_prompts(+Prompts:list) is semidet.
%
%  True when any prompt in Prompts (case-insensitively) contains a phrase
%  that suggests the user is expected to enter long-form text.
fg_suggests_textarea_prompts(Prompts) :-
    member(Prompt, Prompts),
    fg_prompt_atom(Prompt, Text),
    downcase_atom(Text, Lower),
    ( sub_atom(Lower, _, _, _, describe)      -> true
    ; sub_atom(Lower, _, _, _, 'your message') -> true
    ; sub_atom(Lower, _, _, _, 'your comment') -> true
    ; sub_atom(Lower, _, _, _, 'your note')   -> true
    ; sub_atom(Lower, _, _, _, 'write a')     -> true
    ),
    !.

%% fg_prompt_atom(+NormOutput, -Text:atom) is semidet.
%
%  Extract the ground atom text from a norm_output/1 goal.
%  Fails (and does not bind Text) when the argument is not a ground atom.
fg_prompt_atom(norm_output(writeln(T)), T) :- atom(T), !.
fg_prompt_atom(norm_output(write(T)),   T) :- atom(T), !.
fg_prompt_atom(norm_output(print(T)),   T) :- atom(T), !.
fg_prompt_atom(norm_output(format(Fmt)), Fmt) :- atom(Fmt), !.
fg_prompt_atom(norm_output(format(Fmt, _)), Fmt) :- atom(Fmt), !.

% ==========================================================================
% Hidden state carrier
% ==========================================================================

%% build_hidden_inputs(+HiddenVarNames:list, +VN:list, -HiddenInputs:list) is det.
%
%  Build a list of input([type=hidden, name=N, value=V]) terms for every
%  variable name in HiddenVarNames.  The corresponding Prolog variable is
%  looked up in VN (the Name=Var association list).
%
%  These hidden inputs carry accumulated state forward through each HTTP
%  POST to the next step's handler.
build_hidden_inputs([], _, []).
build_hidden_inputs([VarName | Rest], VN, [HiddenInput | RestInputs]) :-
    fg_find_var(VarName, VN, V),
    HiddenInput = input([type=hidden, name=VarName, value=V]),
    build_hidden_inputs(Rest, VN, RestInputs).

%% fg_find_var(+Name, +VN, -Var) is det.
%
%  Look up the Prolog variable associated with Name in a Name=Var list.
fg_find_var(Name, [Name = V | _], V) :- !.
fg_find_var(Name, [_ | Rest], V) :-
    fg_find_var(Name, Rest, V).

% ==========================================================================
% Input field builder
% ==========================================================================

%% build_input_field(+InputType, +VarName, -InputField) is det.
%
%  Build the user-visible input element for the given InputType:
%    text     — input([type=text, name=VarName, autofocus=autofocus])
%    password — input([type=password, name=VarName, autofocus=autofocus])
%    textarea — textarea([name=VarName, autofocus=autofocus, rows='5', cols='40'], '')
%
%  All fields carry autofocus=autofocus so the browser focuses the field
%  automatically when the form page loads.
build_input_field(text, VarName,
                  input([type=text, name=VarName, autofocus=autofocus])) :- !.
build_input_field(password, VarName,
                  input([type=password, name=VarName, autofocus=autofocus])) :- !.
build_input_field(textarea, VarName,
                  textarea([name=VarName, autofocus=autofocus,
                             rows='5', cols='40'], '')) :- !.
build_input_field(_, VarName,
                  input([type=text, name=VarName, autofocus=autofocus])).

% ==========================================================================
% Form assembler
% ==========================================================================

%% generate_form(+Prompts, +InputVarName, +HiddenVarNames, +NextStep,
%%               +InputKind, +VN, -FormTerm) is det.
%
%  Assemble a complete HTML form term for inclusion in reply_html_page/2.
%
%  Form structure (in child order):
%    1. Hidden inputs (one per name in HiddenVarNames) — preserve state.
%    2. Prompt HTML (one element per norm_output/1 in Prompts).
%    3. User input field (type determined by InputKind) — with autofocus.
%    4. Submit button.
%
%  The form posts to Action = '/' ++ NextStep with method=post.
%
%  Prompts        — list of norm_output/1 goals to render as HTML content
%  InputVarName   — atom: name attribute for the user input field
%  HiddenVarNames — list of atom names to carry as hidden fields
%  NextStep       — atom: the next handler name (e.g. step_1)
%  InputKind      — text | password | textarea
%  VN             — Name=Var association list
%  FormTerm       — form([method=post, action=Action], Children)
generate_form(Prompts, InputVarName, HiddenVarNames, NextStep,
              InputKind, VN, Form) :-
    atom_concat('/', NextStep, Action),
    build_hidden_inputs(HiddenVarNames, VN, HiddenInputs),
    maplist(norm_output_to_html_term, Prompts, PromptHtmls),
    build_input_field(InputKind, InputVarName, InputField),
    SubmitInput = input([type=submit, value='Next']),
    append(HiddenInputs, PromptHtmls, Acc),
    append(Acc, [InputField, SubmitInput], FormChildren),
    Form = form([method=post, action=Action], FormChildren).
