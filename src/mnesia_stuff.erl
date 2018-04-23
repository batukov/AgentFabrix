-module(mnesia_stuff).
-export([database_run/1, agents_increase_deals/1, agents_state_dead/1, agents_states_write/4, get_types_stats/0, get_agents_list/0, get_number_of_agents_of_type/1]).
-import(communication, [send_msg/4]).

%% IMPORTANT: The next line must be included
%%            if we want to call qlc:q(...)
-include_lib("stdlib/include/qlc.hrl").

-record(magazine, {gambler, sys_time}).
-record(agents_states, {agent, deals, type, state}).
%
database_run(Node) ->
	spawn(fun() -> db_msg_service(Node) end).
%
db_msg_service(Node) ->
	register(mnesia, self()),
	process_flag(trap_exit, true),
	start_mnesia_magaz(Node),
	db_msg_loop().
%
db_msg_loop() ->
	receive
		{Fabric, state, sys}	-> 	send_msg(Fabric, self(), db_is_fine, sys);
		{Client, Msg, _}	-> 
				case Msg of
					advert -> case request(Client) of
							{fine}  -> send_msg(Client, self(), advert_done, req);
							{error} -> send_msg(Client, self(), cant_sry, req);
							{Value} -> send_msg(Client, self(), Value, req)
						end;
					_	-> ok
				end;
		
		_		-> error
	end,
	db_msg_loop().
	
%
start_mnesia_on_nodes([]) -> ok;
start_mnesia_on_nodes([Head|Tail]) ->
	Pid = spawn(Head, mnesia, start, []),
	start_mnesia_on_nodes(Tail).
start_mnesia_magaz(Nodes) -> 
	mnesia:stop(),
	Deletion = mnesia:delete_schema(Nodes),
	io:format("Deletion ~p~n", [Deletion]),
	Mnesia_scheme = mnesia:create_schema(Nodes),
	
	LeastNodes = lists:delete(node(),Nodes),
	io:format("LeastNodes: ~p~n", [LeastNodes]),
	%Mnesia_added_nodes = mnesia:change_config(extra_db_nodes, LeastNodes),
	Mnesia_start = rpc:multicall(Nodes, application, start, [mnesia]),
%	Mnesia_start = mnesia:start(),
	
%	io:format("Mnesia_added_nodes: ~p~n", [Mnesia_added_nodes]),
	io:format("Mnesia_scheme, Mnesia_start: ~p~n", [{Mnesia_scheme, Mnesia_start}]),
	
	mnesia:delete_table(magazine),
	mnesia:create_table(magazine, [{ram_copies, Nodes}, {attributes, record_info(fields, magazine)}]),
	mnesia:delete_table(agents_states),
	mnesia:create_table(agents_states, [{ram_copies, Nodes}, {attributes, record_info(fields, agents_states)}]),
	mnesia:wait_for_tables([magazine, agents_states], 5000), mnesia:info().
%
request(Gambler) ->
	case do(qlc:q([Advertisment#magazine.gambler || Advertisment <- mnesia:table(magazine)])) of
		[]		-> Fun = fun() -> mnesia:write(#magazine{gambler = Gambler, sys_time = erlang:monotonic_time()}) end,
					mnesia:sync_transaction(Fun), {fine};
		[Head|_]	-> Fun = fun() -> mnesia:delete({magazine, Head}) end,
					mnesia:sync_transaction(Fun),
					{Head};
		_		-> {error}
	end.
%
info() ->
	mnesia:info().
%
show_all() -> 
	Fun = fun() -> qlc:eval( qlc:q([ X || X <- mnesia:table(magazine) ] ))end,
	mnesia:sync_transaction(Fun).
%

do(Q) ->
    F = fun() -> qlc:e(Q) end,
    %{atomic, Val} = mnesia:transaction(F),
    {A, B} = mnesia:sync_transaction(F),
%    io:format("A/B Mnesia: ~p~n", [{A, B}]),
    case A of
    	aborted -> do(Q), io:format("A/B Mnesia: ~p~n", [{A, B}]);
    	atomic -> B
    end.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
agents_increase_deals(Agent) ->
	[{Deals, Type, State}] = do(qlc:q([{NeededAgent#agents_states.deals, NeededAgent#agents_states.type, NeededAgent#agents_states.state} || NeededAgent <- mnesia:table(agents_states), NeededAgent#agents_states.agent =:=Agent])),
	Fun = fun() -> mnesia:delete({agents_states, Agent}), mnesia:write(#agents_states{agent = Agent, deals = Deals+1, type = Type, state = State}) end,
	mnesia:sync_transaction(Fun).
	

%
agents_state_dead(Agent) ->
	Fun = fun() -> 
		[NeededAgent] = mnesia:wread({agents_states, Agent}),
    	mnesia:write(agents_states, NeededAgent#agents_states{state=dead}, write)
    end,
	mnesia:sync_transaction(Fun).
%
agents_states_write(Agent, Deals, Type, State) -> 
					Fun = fun() -> mnesia:write(#agents_states{agent = Agent, deals = Deals, type = Type, state = State}) end,
					mnesia:sync_transaction(Fun).
%
get_types_stats() ->
    TypesList = do(qlc:q([X#agents_states.type || X <- mnesia:table(agents_states)])),
    Set = sets:from_list(TypesList),
    RealTypesList = sets:to_list(Set),
    get_stats_of_type(RealTypesList,[]).
%
get_stats_of_type([], Acc) -> Acc;
get_stats_of_type([Head|Tail], Acc) ->
	StateList = do(qlc:q([X#agents_states.state || X <- mnesia:table(agents_states), X#agents_states.type == Head])),
	{Alive, Dead} = fill_states_acc(StateList, {0,0}),
	get_stats_of_type(Tail, [{Head, Alive, Dead}|Acc]).
%
fill_states_acc([], Acc) -> Acc;
fill_states_acc([Head|Tail], {Alive, Dead}) ->
	case Head of
		dead -> fill_states_acc(Tail, {Alive, Dead +1});
		fine -> fill_states_acc(Tail, {Alive +1, Dead})
	end.
%
get_agents_list() ->
	do(qlc:q([X#agents_states.agent || X <- mnesia:table(agents_states)])).
%
get_number_of_agents_of_type(Type) ->
	Agents = do(qlc:q([X#agents_states.type || X <- mnesia:table(agents_states), X#agents_states.type =:= Type])),
	lists:foldl(fun(X, Sum) -> Sum+1 end, 0, Agents).
%
 








