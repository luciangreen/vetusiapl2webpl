% 200 inputs and outputs, from real runs: io(N, Predicate, Inputs, Output).
io(1,looks_like_html,['Hello <b>World</b>!'],yes).
io(2,html_escape,['<h1>Title</h1> and more'],'&lt;h1&gt;Title&lt;/h1&gt; and more').
io(3,state_round_trip,[3.14],[serialised('3.14'),back(3.14)]).
io(4,normalise_body,[(read_string(user_input,"\n","\r",A,B),writeln(B))],norm_conj(norm_read_string(user_input,"\n","\r",A,B),norm_output(writeln(B)))).
io(5,is_output_goal,[writef('%w',[b])],yes).
io(6,select_input_type,[read_string,'Pin',["Write a long message:"]],password).
io(7,menu_input_kind,[[]],radio).
io(8,convert,["main :-\n    writeln(\"What is your city?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, S),\n    string_concat(\"You chose \", S, R),\n    writeln(R).\n"],[lines(32),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(9,looks_like_html,['<br/>'],yes).
io(10,html_escape,['x > y'],'x &gt; y').
io(11,state_round_trip,["a string"],[serialised('"a string"'),back("a string")]).
io(12,normalise_body,[(A=1,B is A+1,write(B))],norm_conj(norm_goal(A=1),norm_conj(norm_goal(B is A+1),norm_output(write(B))))).
io(13,is_output_goal,[print(z)],yes).
io(14,select_input_type,[read_password,'Notes',["Password:"]],password).
io(15,menu_input_kind,[[menu_choice("1",x)]],radio).
io(16,convert,["main :-\n    writeln(\"1. Add\"), writeln(\"2. Quit\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, C),\n    ( C = \"1\" -> writeln(\"Added\") ; C = \"2\" -> writeln(\"Bye\") ; writeln(\"Pardon?\") ).\n"],[lines(31),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(17,looks_like_html,['Price: $5 & tax'],false).
io(18,html_escape,['<p>Hello</p>'],'&lt;p&gt;Hello&lt;/p&gt;').
io(19,state_round_trip,[[1,2,3]],[serialised('[1,2,3]'),back([1,2,3])]).
io(20,normalise_body,[format("~w~n",[z])],norm_output(format("~w~n",[z]))).
io(21,is_output_goal,[read(x)],false).
io(22,select_input_type,[read_term,'City',["Enter your name:"]],text).
io(23,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x)]],radio).
io(24,convert,["main :-\n    writeln(\"Your food?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, A),\n    writeln(\"And another?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, B),\n    format(\"~w and ~w~n\", [A, B]).\n"],[lines(41),forms(2),predicates([main/0,step_0/1,step_1/1,step_2/1])]).
io(25,looks_like_html,['<script>x</script>'],yes).
io(26,html_escape,['Enter your name:'],'Enter your name:').
io(27,state_round_trip,[f(x,[y])],[serialised('f(x,[y])'),back(f(x,[y]))]).
io(28,normalise_body,[(a,(b;c))],norm_conj(norm_goal(a),norm_disj(norm_goal(b),norm_goal(c)))).
io(29,is_output_goal,[atom_length(a,A)],false).
io(30,select_input_type,[read_password,'Secret',["Please describe the problem in detail:"]],password).
io(31,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x)]],radio).
io(32,convert,["main :-\n    writeln(\"1. Add\"), writeln(\"2. Quit\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, C),\n    ( C = \"1\" -> writeln(\"Added\") ; C = \"2\" -> writeln(\"Bye\") ; writeln(\"Pardon?\") ).\n"],[lines(31),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(33,looks_like_html,['Tom & "Jerry"'],false).
io(34,html_escape,['42'],'42').
io(35,state_round_trip,['Hello World'],[serialised('\'Hello World\''),back('Hello World')]).
io(36,normalise_body,[true],norm_true).
io(37,is_output_goal,[true],false).
io(38,select_input_type,[read_term,'Description',["Choice?"]],text).
io(39,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x)]],radio).
io(40,convert,["main :-\n    writeln(\"Your food?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, A),\n    writeln(\"And another?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, B),\n    format(\"~w and ~w~n\", [A, B]).\n"],[lines(41),forms(2),predicates([main/0,step_0/1,step_1/1,step_2/1])]).
io(41,looks_like_html,['<h1>Title</h1> and more'],yes).
io(42,html_escape,[''],'').
io(43,state_round_trip,[[]],[serialised('[]'),back([])]).
io(44,normalise_body,[!],norm_cut).
io(45,is_output_goal,[writeln(x)],yes).
io(46,select_input_type,[read_string,'Name',[]],text).
io(47,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x)]],select).
io(48,convert,["main :-\n    writeln(\"What is your name?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, S),\n    string_concat(\"Hello, \", S, R),\n    writeln(R).\n"],[lines(32),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(49,looks_like_html,['x > y'],false).
io(50,html_escape,['a < b'],'a &lt; b').
io(51,state_round_trip,[""],[serialised('""'),back("")]).
io(52,normalise_body,[(a,b)],norm_conj(norm_goal(a),norm_goal(b))).
io(53,is_output_goal,[write(y)],yes).
io(54,select_input_type,[read_term,'Password',["Please describe the problem in detail:"]],text).
io(55,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x),menu_choice("6",x)]],select).
io(56,convert,["main :-\n    writeln(\"Your city?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, A),\n    writeln(\"And another?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, B),\n    format(\"~w and ~w~n\", [A, B]).\n"],[lines(41),forms(2),predicates([main/0,step_0/1,step_1/1,step_2/1])]).
io(57,looks_like_html,['<p>Hello</p>'],yes).
io(58,html_escape,['Hello <b>World</b>!'],'Hello &lt;b&gt;World&lt;/b&gt;!').
io(59,state_round_trip,[point(1,2)],[serialised('point(1,2)'),back(point(1,2))]).
io(60,normalise_body,[(a;b)],norm_disj(norm_goal(a),norm_goal(b))).
io(61,is_output_goal,[nl],yes).
io(62,select_input_type,[read_string,'Comment',["Choice?"]],textarea).
io(63,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x),menu_choice("6",x),menu_choice("7",x)]],select).
io(64,convert,["main :-\n    writeln(\"What is your colour?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, S),\n    string_concat(\"Thanks: \", S, R),\n    writeln(R).\n"],[lines(32),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(65,looks_like_html,['Enter your name:'],false).
io(66,html_escape,['<br/>'],'&lt;br/&gt;').
io(67,state_round_trip,['it\'s'],[serialised('\'it\'\'s\''),back('it\'s')]).
io(68,normalise_body,[(a->b)],norm_if_then(norm_goal(a),norm_goal(b))).
io(69,is_output_goal,[format("~w",[a])],yes).
io(70,select_input_type,[read_password,'Age',[]],password).
io(71,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x),menu_choice("6",x),menu_choice("7",x),menu_choice("8",x)]],select).
io(72,convert,["main :-\n    writeln(\"1. Add\"), writeln(\"2. Quit\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, C),\n    ( C = \"1\" -> writeln(\"Added\") ; C = \"2\" -> writeln(\"Bye\") ; writeln(\"Pardon?\") ).\n"],[lines(31),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(73,looks_like_html,['42'],false).
io(74,html_escape,['Price: $5 & tax'],'Price: $5 &amp; tax').
io(75,state_round_trip,[hello],[serialised(hello),back(hello)]).
io(76,normalise_body,[(a->b;c)],norm_if_then_else(norm_goal(a),norm_goal(b),norm_goal(c))).
io(77,is_output_goal,[format(hi)],yes).
io(78,select_input_type,[read_string,'Message',["Write a long message:"]],textarea).
io(79,menu_input_kind,[[menu_choice("1",x)]],radio).
io(80,convert,["main :-\n    writeln(\"What is your colour?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, S),\n    string_concat(\"You chose \", S, R),\n    writeln(R).\n"],[lines(32),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(81,looks_like_html,[''],false).
io(82,html_escape,['<script>x</script>'],'&lt;script&gt;x&lt;/script&gt;').
io(83,state_round_trip,[42],[serialised('42'),back(42)]).
io(84,normalise_body,[(writeln(x),nl)],norm_conj(norm_output(writeln(x)),norm_output(nl))).
io(85,is_output_goal,[write(y)],yes).
io(86,select_input_type,[read_password,'Age',["Password:"]],password).
io(87,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x)]],radio).
io(88,convert,["main :-\n    writeln(\"1. Add\"), writeln(\"2. Quit\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, C),\n    ( C = \"1\" -> writeln(\"Added\") ; C = \"2\" -> writeln(\"Bye\") ; writeln(\"Pardon?\") ).\n"],[lines(31),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(89,looks_like_html,['a < b'],false).
io(90,html_escape,['Tom & "Jerry"'],'Tom &amp; &quot;Jerry&quot;').
io(91,state_round_trip,[-7],[serialised('-7'),back(-7)]).
io(92,normalise_body,[\+a],norm_goal(\+a)).
io(93,is_output_goal,[nl],yes).
io(94,select_input_type,[read_term,'Message',["Enter your name:"]],text).
io(95,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x)]],radio).
io(96,convert,["main :-\n    writeln(\"Your name?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, A),\n    writeln(\"And another?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, B),\n    format(\"~w and ~w~n\", [A, B]).\n"],[lines(41),forms(2),predicates([main/0,step_0/1,step_1/1,step_2/1])]).
io(97,looks_like_html,['Price: $5 & tax'],false).
io(98,html_escape,['Enter your name:'],'Enter your name:').
io(99,state_round_trip,['Hello World'],[serialised('\'Hello World\''),back('Hello World')]).
io(100,normalise_body,[!],norm_cut).
io(101,is_output_goal,[format("~w",[a])],yes).
io(102,select_input_type,[read_password,'Pin',["Write a long message:"]],password).
io(103,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x)]],radio).
io(104,convert,["main :-\n    writeln(\"1. Add\"), writeln(\"2. Quit\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, C),\n    ( C = \"1\" -> writeln(\"Added\") ; C = \"2\" -> writeln(\"Bye\") ; writeln(\"Pardon?\") ).\n"],[lines(31),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(105,looks_like_html,['<script>x</script>'],yes).
io(106,html_escape,['42'],'42').
io(107,state_round_trip,[[]],[serialised('[]'),back([])]).
io(108,normalise_body,[(a,b)],norm_conj(norm_goal(a),norm_goal(b))).
io(109,is_output_goal,[format(hi)],yes).
io(110,select_input_type,[read_term,'Notes',["Password:"]],text).
io(111,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x)]],select).
io(112,convert,["main :-\n    writeln(\"Your name?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, A),\n    writeln(\"And another?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, B),\n    format(\"~w and ~w~n\", [A, B]).\n"],[lines(41),forms(2),predicates([main/0,step_0/1,step_1/1,step_2/1])]).
io(113,looks_like_html,['Tom & "Jerry"'],false).
io(114,html_escape,[''],'').
io(115,state_round_trip,[""],[serialised('""'),back("")]).
io(116,normalise_body,[(a;b)],norm_disj(norm_goal(a),norm_goal(b))).
io(117,is_output_goal,[writef('%w',[b])],yes).
io(118,select_input_type,[read_string,'City',["Enter your name:"]],text).
io(119,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x),menu_choice("6",x)]],select).
io(120,convert,["main :-\n    writeln(\"What is your city?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, S),\n    string_concat(\"Hello, \", S, R),\n    writeln(R).\n"],[lines(32),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(121,looks_like_html,['<h1>Title</h1> and more'],yes).
io(122,html_escape,['a < b'],'a &lt; b').
io(123,state_round_trip,[point(1,2)],[serialised('point(1,2)'),back(point(1,2))]).
io(124,normalise_body,[(a->b)],norm_if_then(norm_goal(a),norm_goal(b))).
io(125,is_output_goal,[print(z)],yes).
io(126,select_input_type,[read_term,'Secret',["Please describe the problem in detail:"]],text).
io(127,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x),menu_choice("6",x),menu_choice("7",x)]],select).
io(128,convert,["main :-\n    writeln(\"Your colour?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, A),\n    writeln(\"And another?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, B),\n    format(\"~w and ~w~n\", [A, B]).\n"],[lines(41),forms(2),predicates([main/0,step_0/1,step_1/1,step_2/1])]).
io(129,looks_like_html,['x > y'],false).
io(130,html_escape,['Hello <b>World</b>!'],'Hello &lt;b&gt;World&lt;/b&gt;!').
io(131,state_round_trip,['it\'s'],[serialised('\'it\'\'s\''),back('it\'s')]).
io(132,normalise_body,[(a->b;c)],norm_if_then_else(norm_goal(a),norm_goal(b),norm_goal(c))).
io(133,is_output_goal,[read(x)],false).
io(134,select_input_type,[read_string,'Description',["Choice?"]],textarea).
io(135,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x),menu_choice("6",x),menu_choice("7",x),menu_choice("8",x)]],select).
io(136,convert,["main :-\n    writeln(\"What is your city?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, S),\n    string_concat(\"Thanks: \", S, R),\n    writeln(R).\n"],[lines(32),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(137,looks_like_html,['<p>Hello</p>'],yes).
io(138,html_escape,['<br/>'],'&lt;br/&gt;').
io(139,state_round_trip,[hello],[serialised(hello),back(hello)]).
io(140,normalise_body,[(writeln(x),nl)],norm_conj(norm_output(writeln(x)),norm_output(nl))).
io(141,is_output_goal,[atom_length(a,A)],false).
io(142,select_input_type,[read_password,'Name',[]],password).
io(143,menu_input_kind,[[]],radio).
io(144,convert,["main :-\n    writeln(\"1. Add\"), writeln(\"2. Quit\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, C),\n    ( C = \"1\" -> writeln(\"Added\") ; C = \"2\" -> writeln(\"Bye\") ; writeln(\"Pardon?\") ).\n"],[lines(31),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(145,looks_like_html,['Enter your name:'],false).
io(146,html_escape,['Price: $5 & tax'],'Price: $5 &amp; tax').
io(147,state_round_trip,[42],[serialised('42'),back(42)]).
io(148,normalise_body,[\+a],norm_goal(\+a)).
io(149,is_output_goal,[true],false).
io(150,select_input_type,[read_string,'Password',["Please describe the problem in detail:"]],password).
io(151,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x)]],radio).
io(152,convert,["main :-\n    writeln(\"What is your food?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, S),\n    string_concat(\"You chose \", S, R),\n    writeln(R).\n"],[lines(32),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(153,looks_like_html,['42'],false).
io(154,html_escape,['<script>x</script>'],'&lt;script&gt;x&lt;/script&gt;').
io(155,state_round_trip,[-7],[serialised('-7'),back(-7)]).
io(156,normalise_body,[(read_string(user_input,"\n","\r",A,B),writeln(B))],norm_conj(norm_read_string(user_input,"\n","\r",A,B),norm_output(writeln(B)))).
io(157,is_output_goal,[writeln(x)],yes).
io(158,select_input_type,[read_password,'Comment',["Choice?"]],password).
io(159,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x)]],radio).
io(160,convert,["main :-\n    writeln(\"1. Add\"), writeln(\"2. Quit\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, C),\n    ( C = \"1\" -> writeln(\"Added\") ; C = \"2\" -> writeln(\"Bye\") ; writeln(\"Pardon?\") ).\n"],[lines(31),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(161,looks_like_html,[''],false).
io(162,html_escape,['Tom & "Jerry"'],'Tom &amp; &quot;Jerry&quot;').
io(163,state_round_trip,[3.14],[serialised('3.14'),back(3.14)]).
io(164,normalise_body,[(A=1,B is A+1,write(B))],norm_conj(norm_goal(A=1),norm_conj(norm_goal(B is A+1),norm_output(write(B))))).
io(165,is_output_goal,[read(x)],false).
io(166,select_input_type,[read_term,'Password',[]],text).
io(167,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x)]],radio).
io(168,convert,["main :-\n    writeln(\"Your food?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, A),\n    writeln(\"And another?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, B),\n    format(\"~w and ~w~n\", [A, B]).\n"],[lines(41),forms(2),predicates([main/0,step_0/1,step_1/1,step_2/1])]).
io(169,looks_like_html,['a < b'],false).
io(170,html_escape,['<h1>Title</h1> and more'],'&lt;h1&gt;Title&lt;/h1&gt; and more').
io(171,state_round_trip,["a string"],[serialised('"a string"'),back("a string")]).
io(172,normalise_body,[format("~w~n",[z])],norm_output(format("~w~n",[z]))).
io(173,is_output_goal,[atom_length(a,A)],false).
io(174,select_input_type,[read_password,'Comment',["Write a long message:"]],password).
io(175,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x)]],select).
io(176,convert,["main :-\n    writeln(\"1. Add\"), writeln(\"2. Quit\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, C),\n    ( C = \"1\" -> writeln(\"Added\") ; C = \"2\" -> writeln(\"Bye\") ; writeln(\"Pardon?\") ).\n"],[lines(31),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(177,looks_like_html,['Hello <b>World</b>!'],yes).
io(178,html_escape,['x > y'],'x &gt; y').
io(179,state_round_trip,[[1,2,3]],[serialised('[1,2,3]'),back([1,2,3])]).
io(180,normalise_body,[(a,(b;c))],norm_conj(norm_goal(a),norm_disj(norm_goal(b),norm_goal(c)))).
io(181,is_output_goal,[true],false).
io(182,select_input_type,[read_term,'Age',["Password:"]],text).
io(183,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x),menu_choice("6",x)]],select).
io(184,convert,["main :-\n    writeln(\"Your city?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, A),\n    writeln(\"And another?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, B),\n    format(\"~w and ~w~n\", [A, B]).\n"],[lines(41),forms(2),predicates([main/0,step_0/1,step_1/1,step_2/1])]).
io(185,looks_like_html,['<br/>'],yes).
io(186,html_escape,['<p>Hello</p>'],'&lt;p&gt;Hello&lt;/p&gt;').
io(187,state_round_trip,[f(x,[y])],[serialised('f(x,[y])'),back(f(x,[y]))]).
io(188,normalise_body,[true],norm_true).
io(189,is_output_goal,[writeln(x)],yes).
io(190,select_input_type,[read_string,'Message',["Enter your name:"]],textarea).
io(191,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x),menu_choice("6",x),menu_choice("7",x)]],select).
io(192,convert,["main :-\n    writeln(\"What is your colour?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, S),\n    string_concat(\"Hello, \", S, R),\n    writeln(R).\n"],[lines(32),forms(1),predicates([main/0,step_0/1,step_1/1])]).
io(193,looks_like_html,['Tom & "Jerry"'],false).
io(194,html_escape,['a < b'],'a &lt; b').
io(195,state_round_trip,['it\'s'],[serialised('\'it\'\'s\''),back('it\'s')]).
io(196,normalise_body,[(writeln(x),nl)],norm_conj(norm_output(writeln(x)),norm_output(nl))).
io(197,is_output_goal,[write(y)],yes).
io(198,select_input_type,[read_term,'Pin',["Write a long message:"]],text).
io(199,menu_input_kind,[[menu_choice("1",x),menu_choice("2",x),menu_choice("3",x),menu_choice("4",x),menu_choice("5",x),menu_choice("6",x),menu_choice("7",x),menu_choice("8",x)]],select).
io(200,convert,["main :-\n    writeln(\"Your city?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, A),\n    writeln(\"And another?\"),\n    read_string(user_input, \"\\n\", \"\\r\", _, B),\n    format(\"~w and ~w~n\", [A, B]).\n"],[lines(41),forms(2),predicates([main/0,step_0/1,step_1/1,step_2/1])]).
