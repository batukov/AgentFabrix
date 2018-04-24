%%%-------------------------------------------------------------------
%% @doc new_proj public API
%% @end
%%%-------------------------------------------------------------------

-module(server).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).
-import(trades_mech,[croupier/0]).
-import(agent,[agent_start/4]).
-import(mnesia_stuff,[database_run/1, get_types_stats/0, get_agents_list/0, get_number_of_agents_of_type/1, agents_states_write/4, add_absent_nodes_to_mnesia_cluster_from_list/1]).
-import(communication, [send_msg/4]).
%-import(agents_state_database, [ ).


%./_build/default/rel/server/bin/server -noshell




%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    server_sup:start_link(),
%    application:ensure_all_started(mnesia, permanent),
	server(20070, 20071).

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

server(Port, PortSpam) ->
	io:format("hey there !!!~n"),
	HostNames = net_adm:host_file(),
	NodeNames = net_adm:names(),
	Nodes = net_adm:world(verbose),
	io:format("world: ~p~n", [Nodes]),
	io:format("Names: ~p~n", [NodeNames]),
	io:format("Pool: ~p~n", [HostNames]),
	
	Path = filename:dirname(code:which(?MODULE)),
	code:add_path(Path),
	
	{ModS, BinS, FileS} = code:get_object_code(server),
	{_RepliesS, BadNodesS} = rpc:multicall(Nodes, code, load_binary, [ModS, FileS, BinS]),
	io:format("Replies: ~p~n", [{_RepliesS, BadNodesS}]),
	
	{ModA, BinA, FileA} = code:get_object_code(agent),
	{_RepliesA, BadNodesA} = rpc:multicall(Nodes, code, load_binary, [ModA, FileA, BinA]),
	io:format("Replies: ~p~n", [{_RepliesA, BadNodesA}]),
	
	{ModT, BinT, FileT} = code:get_object_code(trades_mech),
	{_RepliesT, BadNodesT} = rpc:multicall(Nodes, code, load_binary, [ModT, FileT, BinT]),
	io:format("Replies: ~p~n", [{_RepliesT, BadNodesT}]),
	
	{ModM, BinM, FileM} = code:get_object_code(mnesia_stuff),
	{_RepliesM, BadNodesM} = rpc:multicall(Nodes, code, load_binary, [ModM, FileM, BinM]),
	io:format("Replies: ~p~n", [{_RepliesM, BadNodesM}]),
	
	{ModC, BinC, FileC} = code:get_object_code(communication),
	{_RepliesC, BadNodesC} = rpc:multicall(Nodes, code, load_binary, [ModC, FileC, BinC]),
	io:format("Replies: ~p~n", [{_RepliesC, BadNodesC}]),
  
  case gen_udp:open(Port, [list, {active, false}]) of 
	{error, Reason} -> io:format("server opening failed ~p ~n", [Reason]);	
	{ok, Socket} ->   io:format("server opened socket: ~p ~n",[Socket]),	
	register(server, self()),
	io:format("server pid is ~p~n", [self()]),
	process_flag(trap_exit, true),
	CroPid = croupier(),
	MnesiaPid = database_run(Nodes),
	AgentsTable = ets:new(agents_table, [named_table, set, private, {keypos, 1}]),
%	AgentStatsTable = ets:new(agents_stats_table, [named_table, set, public, {keypos, 1}]),
	ClientsTable = ets:new(clients_table, [named_table, set, private, {keypos, 1}]),
	SystemTable = ets:new(system_table, [named_table, set, public, {keypos, 1}]),
	ets:insert(system_table, 	[{socket, Socket},
					{port_client, Port},
					{port_spam, PortSpam},
					{cro_pid, CroPid},
					{db_pid, MnesiaPid},
					{round_nodes, Nodes}]),
	loop(Socket, CroPid, MnesiaPid)
  end.
%
loop(Socket, Croupier, Mnesia) ->
  inet:setopts(Socket, [{active, once}]),
  receive
    {udp, Socket, SenderAddress, SenderPort, Bin} -> io:format("server received:~p ~n",[Bin]), 	
    										case ets:match(clients_table, {Socket, SenderAddress, SenderPort}) of
    											[] -> ets:insert(clients_table, {Socket, SenderAddress, SenderPort});
    											[_] -> ok
    										end,
    										[Head|Tail] = string:tokens(Bin, " "),
											case Head of
											
											
											
												"spawn"  ->   [Value, Type] = Tail, case string:to_integer(Value) of
																{error,no_integer} -> send_answer(Socket, SenderAddress, SenderPort, "not interger value");
																{Val, _} -> spawn_agents(Val, Croupier, Mnesia, list_to_atom(Type)),
																			 send_answer(Socket, SenderAddress, SenderPort, "threads_created")
												  				end;
											  	"start"  	->  ListOfThreads = get_agents_list(),	
															  	io:format("ListOfThreads: ~p~n", [ListOfThreads]),
																send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("~p started",[ListOfThreads]))),
															   	ask_agents(start, ListOfThreads);
											   	"show_agents"->  ListOfThreads = get_agents_list(),	
%																send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("~p started",[ListOfThreads]))),
															   	ask_agents(state, ListOfThreads);
												"stop"  	->  ListOfThreads = get_agents_list(),	
															   send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("~p stopped",[ListOfThreads]))),
															   	ask_agents(stop, ListOfThreads);
												"show_all" 	-> {_, ListOfThreads} = process_info(self(), links),
															   SortedList = lists:sort(ListOfThreads),
															   send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format(" all the processes~p",[SortedList])));
											   	"stats" ->  	Stats = get_types_stats(),
																send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("s: ~p",[Stats])));
												"killem_all" ->ListOfThreads = get_agents_list(),	
															   send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("~p stopped",[ListOfThreads]))),
															   	ask_agents(die, ListOfThreads);
												"kill" -> 	[Value] = Tail, ExistingThreads = registered(),
																case [Thread || Thread <- ExistingThreads, Thread =:= list_to_atom(Value)] of
																	[] -> 	send_answer(Socket, SenderAddress, SenderPort,"no such process");
																	[_] ->	exit(list_to_pid(Value), kill),
															 			send_answer(Socket, SenderAddress, SenderPort, "process is down")
																end;
																
																
																
												"sys" ->	[SysWord| Cmd] = Tail,
																case SysWord of
																	"nodes" ->  [CmdWordNodes|CmdWordNodesValue]= Cmd,
																				case CmdWordNodes of
																					"add" 	-> case string:to_integer(CmdWordNodesValue) of
																								{error,no_integer} -> send_answer(Socket, SenderAddress, SenderPort, "not interger value");
																								{CmdWordNodesVal, _} -> sys_nodes_add(CmdWordNodesVal, Socket, SenderAddress, SenderPort)
																				  				end;
																								
																					"show"	-> sys_nodes_show(Socket, SenderAddress, SenderPort);
																					_ 		-> send_answer(Socket, SenderAddress, SenderPort, "unknown command word")
																				end;
																	"hosts"	->	[CmdWordHosts|CmdWordHostsValue]= Cmd,
																				case CmdWordHosts of
																					"del"	-> sys_hosts_del();
																					"add"	-> sys_hosts_add(CmdWordHostsValue, Socket, SenderAddress, SenderPort);
																					"show"	-> sys_hosts_show(Socket, SenderAddress, SenderPort);
																					_ 		-> send_answer(Socket, SenderAddress, SenderPort, "unknown command word")
																				end;
																	"dbase"	->	[CmdWordDbase|_]= Cmd,
																				case CmdWordDbase of
																					"save"	-> sys_dbase_save();
																					_ 		-> send_answer(Socket, SenderAddress, SenderPort, "unknown command word")
																				end;
																	"msg"	->	[CmdWordMsg|CmdWordMsgValue]= Cmd,
																				case CmdWordMsg of
																					"do_spam"	-> sys_msg_do_spam();
																					"stop_spam"	-> sys_msg_stop_spam();
																					_ 		-> send_answer(Socket, SenderAddress, SenderPort, "unknown command word")
																				end;
																	_		-> send_answer(Socket, SenderAddress, SenderPort, "unknown system word")
																end;
												
												
												
												
												
												_	 	-> send_answer(Socket, SenderAddress, SenderPort, "unknown message")
											end;
												
    {Address, Msg, _} 		-> send_to_all_clients(lists:flatten(io_lib:format("thread ~p has ~p~n", [Address, Msg])));
   	{_} 					-> send_to_all_clients("unknown message")
    
  end,
  loop(Socket, Croupier,Mnesia).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% SYSTEM WORDS STUFF
find_elem(List, Elem) ->
	Result = [X|| X <- List, X =:= Elem],
	case Result of
		[_] -> found;
		[]	-> not_found
	end.
%
sys_nodes_add(Value, Socket, SenderAddress, SenderPort) ->
	UsedNodesList = ets:lookup(system_table, round_nodes),
	case ets:info(nodes_available) of
		undefined -> send_answer(Socket, SenderAddress, SenderPort, "u should chk for nodes first");
		_ -> 	D = ets:lookup(nodes_available, Value),
				case D of
					[{_, AskedNode}] -> [{ _, NodesList}] =	ets:lookup(system_table, round_nodes),
										case find_elem(NodesList, AskedNode) of
											found 		-> send_answer(Socket, SenderAddress, SenderPort, "cant add node, exists already and able to use");
											not_found 	-> NewNodesList = [AskedNode|NodesList], 
															ets:insert(system_table, {round_nodes, NewNodesList}), 
															BeforeNodes = mnesia:system_info(db_nodes),
															io:format("BeforeNodes: ~p~n", [BeforeNodes]),
															add_absent_nodes_to_mnesia_cluster_from_list(NewNodesList),
															AfterNodes = mnesia:system_info(db_nodes),
															io:format("BeforeNodes: ~p~n", [AfterNodes]),
															send_answer(Socket, SenderAddress, SenderPort, "node added")
										end, ets:delete(nodes_available);
					[_]				->	send_answer(Socket, SenderAddress, SenderPort, "unpredicted behaviour");
					[]				->	send_answer(Socket, SenderAddress, SenderPort, "wrong value, sry mon")
				end
	end,
	ok.
%
sys_nodes_show(Socket, SenderAddress, SenderPort) ->
	NodesAvailable = net_adm:world(verbose),
	ListLength = lists:seq(1, length(NodesAvailable)),
	NodesTuplesList = lists:zip(ListLength,NodesAvailable),
	case ets:info(nodes_available) of
		undefined	-> fine;
		_ ->	ets:delete(nodes_available)
	end,
	ets:new(nodes_available, [named_table, set, public, {keypos, 1}]),
	ets:insert(nodes_available, NodesTuplesList),
	[{ _, NodesList}] =	ets:lookup(system_table, round_nodes),
	send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("Available nodes are: ~p",[NodesTuplesList]))),
	send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("Used nodes are: ~p",[NodesList]))),
	ok.
%
get_file_text(Name, Buffer)->
	case io:get_line(Name, '') of
		eof -> Buffer;
		String	-> NewBuffer = [String|Buffer], get_file_text(Name, NewBuffer)
	end.
%
set_file_text(Name, [])-> ok;
set_file_text(Name, [Head|Tail])->
	io:format(Name, "\~s\~n", [Head]),
	set_file_text(Name, Tail).

%
sys_hosts_add(Hostname, Socket, SenderAddress, SenderPort) ->
	{OpenedR, FileR} = file:open(".hosts.erlang", read),
	case OpenedR of
		error	-> send_answer(Socket, SenderAddress, SenderPort, "failed to open .hosts.erlang file to read, smthing goes wrong");
		ok		-> 	OldText = get_file_text(FileR, []),
					file:close(FileR),
					NewHostName = "'" ++ Hostname ++ "'.",
					NewText = [NewHostName|OldText],
					{OpenedW, FileW} = file:open(".hosts.erlang", write),
					case OpenedW of
						error	-> send_answer(Socket, SenderAddress, SenderPort, "failed to open .hosts.erlang file to write, smthing goes wrong");
						ok		-> set_file_text(FileW, NewText), file:close(FileW)
					end
	end,
	ok.
%
sys_hosts_del() ->
	ok.
%
sys_hosts_show(Socket, SenderAddress, SenderPort) ->
	HostsPool = net_adm:host_file(),
	ListLength = lists:seq(1, length(HostsPool)),
	HostsTuplesList = lists:zip(ListLength, HostsPool),
	case ets:info(hosts_mentioned) of
		undefined	-> fine;
		_ ->	ets:delete(hosts_mentioned)
	end,
	ets:new(hosts_mentioned, [named_table, set, public, {keypos, 1}]),
	ets:insert(hosts_mentioned, HostsTuplesList),
	send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("Available hosts: ~p",[HostsTuplesList]))),
	ok.
%
sys_dbase_save() ->
	ok.
%
sys_msg_do_spam() ->
	ok.
%
sys_msg_stop_spam() ->
	ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% PROCESS GENERATOR
spawn_agents(Value, Croupier, Mnesia, Type) ->
	NumberOfAgents = get_number_of_agents_of_type(Type),
	NodesList =	ets:lookup(system_table, round_nodes),
	Sasl = rpc:multicall(NodesList, application, start, [sasl]),
	OS_Mon = rpc:multicall(NodesList, application, start, [os_mon]),
	zerg_processes(NumberOfAgents, NumberOfAgents+Value, Croupier, Mnesia, Type, NodesList).
%
get_node_with_lowest_load([], Acc) -> Acc;
get_node_with_lowest_load([Head|Tail], Acc) ->
	ThisNode = get_node_load(Head),
	NewAcc = [ThisNode|Acc],
	get_node_with_lowest_load(Tail, NewAcc).
%
get_node_load(Node) ->
	Load = rpc:call(Node, cpu_sup, avg1, []),
	{Node, Load}.
%
get_lowest_load_of_nodes([_], {MinName, _}) -> MinName;
get_lowest_load_of_nodes([Head|Tail], {MinName, MinVal}) ->
	{Name, Load} = Head,
	io:format("Name: ~p~n", [Name]),
	case (MinVal - Load) < 0 of
		true	-> 	get_lowest_load_of_nodes(Tail, {Name, Load});
		false	-> 	get_lowest_load_of_nodes(Tail, {MinName, MinVal})
	end.
%
find_suitable_node(Hosts) ->
	ResultVal = get_node_with_lowest_load(Hosts, []),
	ThisNodeLoad = rpc:call(node(), cpu_sup, avg1, []),
	Lowest = get_lowest_load_of_nodes(ResultVal, { node(),ThisNodeLoad}).
%
zerg_processes(Number, NeededNumber, Croupier, Mnesia, Type, NodesList) ->
	case Number of
		NeededNumber -> {ok};
		_ -> 	Owner = self(),
%				[Head | Tail] = Hosts,
				NodeToSpawn = find_suitable_node(NodesList),
				Pid = spawn_link(NodeToSpawn, agent, agent_start, [Owner, Croupier, Mnesia, Type]),
				agents_states_write(Pid, 0, Type, fine),
				global:register_name(list_to_atom(pid_to_list(Pid)), Pid),
				NumberOfAgents = get_number_of_agents_of_type(Type),
				zerg_processes(NumberOfAgents, NeededNumber, Croupier, Mnesia, Type, NodesList)
	end.
%
ask_agents(_,[])-> io:format("agents asked~n");
ask_agents(Request, [Head|Tail])->
	Agent = Head,
	send_msg(Agent, self(), Request, sys),
	ask_agents(Request,Tail).
%
send_answer(Socket, Address, Port, Msg) ->
	gen_udp:send(Socket, Address, Port, Msg).
%
send_to_all_clients(Msg) ->
	List = ets:match(clients_table, {'$1', '$2', '$3'}),
	send_to_client(List, Msg).
%
send_to_client([], _) -> okay;
send_to_client([[Socket, Address, Port]|Tail], Msg) ->
	gen_udp:send(Socket, Address, Port, Msg),
	send_to_client(Tail, Msg).

