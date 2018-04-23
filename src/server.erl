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
-import(mnesia_stuff,[database_run/1, get_types_stats/0, get_agents_list/0, get_number_of_agents_of_type/1, agents_states_write/4]).
-import(communication, [send_msg/4]).
%-import(agents_state_database, [ ).


%./_build/default/rel/server/bin/server -noshell




%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    server_sup:start_link(),
%    application:ensure_all_started(mnesia, permanent),
	server(20070).

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

server(Port) ->
	io:format("hey there !!!~n"),
	HostsPool = net_adm:host_file(),
	Names = net_adm:names(),
	Hosts = net_adm:world(verbose),
	io:format("world: ~p~n", [Hosts]),
	io:format("Names: ~p~n", [Names]),
	io:format("Pool: ~p~n", [HostsPool]),
	
	Path = filename:dirname(code:which(?MODULE)),
	code:add_path(Path),
	
	{ModS, BinS, FileS} = code:get_object_code(server),
	{_RepliesS, BadNodesS} = rpc:multicall(Hosts, code, load_binary, [ModS, FileS, BinS]),
	io:format("Replies: ~p~n", [{_RepliesS, BadNodesS}]),
	
	{ModA, BinA, FileA} = code:get_object_code(agent),
	{_RepliesA, BadNodesA} = rpc:multicall(Hosts, code, load_binary, [ModA, FileA, BinA]),
	io:format("Replies: ~p~n", [{_RepliesA, BadNodesA}]),
	
	{ModT, BinT, FileT} = code:get_object_code(trades_mech),
	{_RepliesT, BadNodesT} = rpc:multicall(Hosts, code, load_binary, [ModT, FileT, BinT]),
	io:format("Replies: ~p~n", [{_RepliesT, BadNodesT}]),
	
	{ModM, BinM, FileM} = code:get_object_code(mnesia_stuff),
	{_RepliesM, BadNodesM} = rpc:multicall(Hosts, code, load_binary, [ModM, FileM, BinM]),
	io:format("Replies: ~p~n", [{_RepliesM, BadNodesM}]),
	
	{ModC, BinC, FileC} = code:get_object_code(communication),
	{_RepliesC, BadNodesC} = rpc:multicall(Hosts, code, load_binary, [ModC, FileC, BinC]),
	io:format("Replies: ~p~n", [{_RepliesC, BadNodesC}]),
  
  case gen_udp:open(Port, [list, {active, false}]) of 
	{error, Reason} -> io:format("server opening failed ~p ~n", [Reason]);	
	{ok, Socket} ->   io:format("server opened socket: ~p ~n",[Socket]),	
	register(server, self()),
	io:format("server pid is ~p~n", [self()]),
	process_flag(trap_exit, true),
	CroPid = croupier(),
	MnesiaPid = database_run(Hosts),
	AgentsTable = ets:new(agents_table, [named_table, set, private, {keypos, 1}]),
%	AgentStatsTable = ets:new(agents_stats_table, [named_table, set, public, {keypos, 1}]),
	ClientsTable = ets:new(clients_table, [named_table, set, private, {keypos, 1}]), 					% creating databse
	loop(Socket, CroPid, MnesiaPid, Hosts)
  end.
%
loop(Socket, Croupier, Mnesia, Hosts) ->
  inet:setopts(Socket, [{active, once}]),
  receive
    {udp, Socket, SenderAddress, SenderPort, Bin} -> io:format("server received:~p ~n",[Bin]), 	
    										case ets:match(clients_table, {Socket, SenderAddress, SenderPort}) of
    											[] -> ets:insert(clients_table, {Socket, SenderAddress, SenderPort});
    											[_] -> ok
    										end,
    										[Head|Tail] = string:tokens(Bin, " "),
											case [Head] of
												["spawn"]  ->   [Value, Type] = Tail, case string:to_integer(Value) of
																{error,no_integer} -> send_answer(Socket, SenderAddress, SenderPort, "not interger value");
																{Val, _} -> spawn_agents(Val, Croupier, Mnesia, list_to_atom(Type), Hosts),
																			 send_answer(Socket, SenderAddress, SenderPort, "threads_created")
												  				end;
											  	["start"]  	->  ListOfThreads = get_agents_list(),	
															  	io:format("ListOfThreads: ~p~n", [ListOfThreads]),
																send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("~p started",[ListOfThreads]))),
															   	ask_agents(start, ListOfThreads);
											   	["show_agents"]->  ListOfThreads = get_agents_list(),	
%																send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("~p started",[ListOfThreads]))),
															   	ask_agents(state, ListOfThreads);
												["stop"]  	->  ListOfThreads = get_agents_list(),	
															   send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("~p stopped",[ListOfThreads]))),
															   	ask_agents(stop, ListOfThreads);
												["show_all"] 	-> {_, ListOfThreads} = process_info(self(), links),
															   SortedList = lists:sort(ListOfThreads),
															   send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format(" all the processes~p",[SortedList])));
											   	["stats"] ->  	Stats = get_types_stats(),
																send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("s: ~p",[Stats])));
												["killem_all"] ->ListOfThreads = get_agents_list(),	
															   send_answer(Socket, SenderAddress, SenderPort, lists:flatten(io_lib:format("~p stopped",[ListOfThreads]))),
															   	ask_agents(die, ListOfThreads);
												["kill"] -> 	[Value] = Tail, ExistingThreads = registered(),
																case [Thread || Thread <- ExistingThreads, Thread =:= list_to_atom(Value)] of
																	[] -> 	send_answer(Socket, SenderAddress, SenderPort,"no such process");
																	[_] ->	exit(list_to_pid(Value), kill),
															 			send_answer(Socket, SenderAddress, SenderPort, "process is down")
																end;
												[]	 	-> send_answer(Socket, SenderAddress, SenderPort, "try to type something");
												[_]	 	-> send_answer(Socket, SenderAddress, SenderPort, "unknown message")
											end;
												
    {Address, Msg, _} 		-> send_to_all_clients(lists:flatten(io_lib:format("thread ~p has ~p~n", [Address, Msg])));
   	{_} 					-> send_to_all_clients("unknown message")
    
  end,
  loop(Socket, Croupier,Mnesia, Hosts).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% PROCESS GENERATOR
spawn_agents(Value, Croupier, Mnesia, Type, Hosts) ->
	NumberOfAgents = get_number_of_agents_of_type(Type),
	Sasl = rpc:multicall(Hosts, application, start, [sasl]),
%	io:format("Sasl: ~p~n", [Sasl]),
	OS_Mon = rpc:multicall(Hosts, application, start, [os_mon]),
%	io:format("Sasl: ~p~n", [OS_Mon]),

	zerg_processes(NumberOfAgents, NumberOfAgents+Value, Croupier, Mnesia, Type, Hosts).
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
%	io:format("Sasl: ~p~n", [ResultVal]),
	ThisNodeLoad = rpc:call(node(), cpu_sup, avg1, []),
	Lowest = get_lowest_load_of_nodes(ResultVal, { node(),ThisNodeLoad}).
%	io:format("Lowest: ~p~n", [Lowest]),
%
zerg_processes(Number, NeededNumber, Croupier, Mnesia, Type, Hosts) ->
	case Number of
		NeededNumber -> {ok};
		_ -> 	Owner = self(),
%				[Head | Tail] = Hosts,
				NodeToSpawn = find_suitable_node(Hosts),
				Pid = spawn_link(NodeToSpawn, agent, agent_start, [Owner, Croupier, Mnesia, Type]),
				agents_states_write(Pid, 0, Type, fine),
				global:register_name(list_to_atom(pid_to_list(Pid)), Pid),
				NumberOfAgents = get_number_of_agents_of_type(Type),
				zerg_processes(NumberOfAgents, NeededNumber, Croupier, Mnesia, Type, Hosts)
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

