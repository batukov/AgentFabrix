-module(agents_state_database).
-export([start_mnesia_agents/1, agents_increase_deals/1, agents_state_dead/1, agents_states_write/4, get_types_stats/0, get_agents_list/0, get_number_of_agents_of_type/1]).

-include_lib("stdlib/include/qlc.hrl").

-record(agents_states, {agent, deals, type, state}).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% AGENTS DATABASE
start_mnesia_agents(Node) -> 
	Schema = mnesia:create_schema([Node]),
	Started = mnesia:start(),
	io:format("schema, started: ~p~n", [{Schema, Started}]),
	mnesia:wait_for_tables([agents_states], 5000),
	mnesia:delete_table(agents_states),
	mnesia:create_table(agents_states, [{attributes, record_info(fields, agents_states)}]).
%
do(Q) ->
    F = fun() -> qlc:e(Q) end,
    {atomic, Val} = mnesia:transaction(F),
    Val.
%
agents_increase_deals(Agent) ->
	[{Deals, Type, State}] = do(qlc:q([{NeededAgent#agents_states.deals, NeededAgent#agents_states.type, NeededAgent#agents_states.state} || NeededAgent <- mnesia:table(agents_states), NeededAgent#agents_states.agent =:=Agent])),
	Fun = fun() -> mnesia:delete({agents_states, Agent}), mnesia:write(#agents_states{agent = Agent, deals = Deals+1, type = Type, state = State}) end,
	mnesia:transaction(Fun).
	

%
agents_state_dead(Agent) ->
%	{Deals, Type} = do(qlc:q([{NeededAgent#magazine.deals, NeededAgent#magazine.type} || NeededAgent <- mnesia:table(agents_states), NeededAgent=:=Agent]))
	Fun = fun() -> 
		[NeededAgent] = mnesia:wread({agents_states, Agent}),
    	mnesia:write(agents_states, NeededAgent#agents_states{state=dead}, write)
    end,
	mnesia:transaction(Fun).
%
agents_states_write(Agent, Deals, Type, State) ->
					Fun = fun() -> mnesia:write(#agents_states{agent = Agent, deals = Deals, type = Type, state = State}) end,
					mnesia:transaction(Fun).
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
	io:format("Type: ~p~n", [Type]),	
	Agents = do(qlc:q([X#agents_states.type || X <- mnesia:table(agents_states), X#agents_states.type == Type])),
	io:format("Agents: ~p~n", [Agents]),
	lists:foldl(fun(X, Sum) -> Sum+1 end, 0, Agents).
%







