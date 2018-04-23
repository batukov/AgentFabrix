-module(agent).

-export([agent_start/4]).
-import(communication, [send_msg/4]).
-import(mnesia_stuff, [agents_increase_deals/1, agents_state_dead/1, agents_states_write/4]).

%-on_load(init/0).

%-define(APPNAME, agent_maths).
%-define(LIBNAME, server).

% AGENTS STATES

%  - STATES: free -> advert_done -> going_to_deal -> deal_done -> bet_done -> free // extra stopped
%%%% - ACTIONS:advert -> wait_for_call -> ask_for_deal/get_deal -> do_bet -> wait_for_result // extra waiting_for_call_to_start

%free
%%%%advert
%advert_done
%%%%wait_for_call 
%going_to_deal
%%%%ask_for_deal
%%%%get_deal
%deal_done
%%%%do_bet
%bet_done
%%%%wait_for_result
%free

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NIF STUFF
%init() ->
%    SoName = case code:priv_dir(?APPNAME) of
%        {error, bad_name} ->
%            case filelib:is_dir(filename:join(["..", priv])) of
%                true ->
%                    filename:join(["..", priv, ?LIBNAME]);
%                _ ->
%                    filename:join([priv, ?LIBNAME])
%            end;
%        Dir ->
%            filename:join(Dir, ?LIBNAME)
%    end,
%erlang:load_nif(SoName, 0).
%
%not_loaded(Line) ->
%	exit({not_loaded, [{module, ?MODULE}, {line, Line}]}).
%
%calc(_) ->
%	not_loaded(?LINE).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%	Ss = ?MODULE:calc(Number),
%	io:format("ss: ~p~n", [self()]),

%
agent_play_behaviour() ->
	[{_, _, _, _, _, _, _, _, _, Type}] = ets:lookup(list_to_atom(pid_to_list(self())), self()),
%	Result = ?MODULE:calc(Type).
	case Type of
		type_a -> 0;
		type_b -> 1;
		type_c ->	random:seed(erlang:now()), 
					rand:uniform(2)-1		
	end.
%
agent_start(Fabric, Croupier, Amnesia, Type) ->
	ets:new(list_to_atom(pid_to_list(self())), [named_table, set, private, {keypos, 1}]), 					% creating databse
	ets:insert(list_to_atom(pid_to_list(self())), {self(), 100, free, advert, Fabric, Croupier, Amnesia, self(), denied, Type}),	% adding init data to db
	io:format("am here~n"),
	agent_process(). 													% starting agent process
%
agent_process() ->
	case ets:lookup(list_to_atom(pid_to_list(self())), self()) of
		[{_, 0, _, _, _, Trader, _, _, _, _}] -> send_msg(Trader, self(), dead, req), io:format ("~p is dead ~n", [self()]), set_dead(), exit(self(), kill);
		_ -> ok
	end,
	call_action(),
	[{_, _, _, _, Fabric, Croupier, Amnesia, _, _, _}] = ets:lookup(list_to_atom(pid_to_list(self())), self()),
	receive
		{Address, Msg, _} 	-> case Address of
						Fabric	->	case Msg of
									state 	-> send_msg (Fabric, self(), ets:lookup(list_to_atom(pid_to_list(self())), self()), sys);
									start 	-> new_agent_permission(allowed)		;
									stop	-> new_agent_permission(denied)			;
									die   	-> io:format ("~p is dead ~n", [self()]), set_dead(), exit(self(), kill); %send_msg (Fabric, self(), okay, sys)	;
									_	-> error
								end;
						Amnesia -> 	case Msg of
									advert_done-> new_agent_stuff(advert_done, wait_for_call);
									Opponent-> new_agent_stuff_opp(going_to_deal, ask_for_deal, Opponent)
								end;
						Croupier->	case Msg of
									{Gambler, dead} -> check_opponent(Gambler);
									bet_got	-> new_agent_stuff(bet_done, wait_for_result)	;
									Val  	-> new_agent_stuff_val(Val, free, advert), increment_number_of_deals()
								end;
						SomeAgent->	case Msg of
									wanna_play -> new_agent_stuff_opp(going_to_deal, get_deal, SomeAgent);
									sure_thing -> new_agent_stuff_opp(deal_done, do_bet, SomeAgent);
									_     -> error
								end;
						_	->	error
						end;
		_			-> error
	after 2000 ->
		new_agent_stuff(free, advert)
	end,
	agent_process().
%
call_action() ->
	[{_, _, _, Action, Fabric, Croupier, Amnesia, Opponent, Permission, _}] = ets:lookup(list_to_atom(pid_to_list(self())), self()),
	case Action of
		
		advert		-> case Permission of
					denied -> new_agent_stuff(free, advert);
					_ -> send_msg(Amnesia, self(), advert, req)
				   end;
		ask_for_deal-> send_msg(Opponent, self(), wanna_play, req);
		get_deal	-> send_msg(Opponent, self(), sure_thing, req), send_msg(Croupier, self(), {agent_play_behaviour(), Opponent}, req);
		do_bet		-> send_msg(Croupier, self(), {agent_play_behaviour(), Opponent}, req);
		_ 		-> waiting
	end.
%
new_agent_permission(Permission) ->
	[{_, Coins, State, Action, Fabric, Croupier, Amnesia, Opponent, _, Type}] = ets:lookup(list_to_atom(pid_to_list(self())), self()),
	ets:insert(list_to_atom(pid_to_list(self())), {self(), Coins, State, Action, Fabric, Croupier, Amnesia, Opponent, Permission, Type}).
%
check_opponent(Gambler) ->
	[{_, Coins, State, Action, Fabric, Croupier, Amnesia, Opponent, Permission, Type}] = ets:lookup(list_to_atom(pid_to_list(self())), self()),
	case Gambler of
		Opponent -> new_agent_stuff(free, advert);
		_ -> nothing
	end.
%
new_agent_stuff(NewState, NewAction) ->
	[{_, CurCoins, _, _, Fabric, Croupier, Amnesia, Opponent, Permission, Type}] = ets:lookup(list_to_atom(pid_to_list(self())), self()),
	ets:insert(list_to_atom(pid_to_list(self())), {self(), CurCoins, NewState, NewAction, Fabric, Croupier, Amnesia, Opponent, Permission, Type}).
%
new_agent_stuff_opp(NewState, NewAction, Opponent) ->
	[{_, CurCoins, _, _, Fabric, Croupier, Amnesia, _, Permission, Type}] = ets:lookup(list_to_atom(pid_to_list(self())), self()),
	ets:insert(list_to_atom(pid_to_list(self())), {self(), CurCoins, NewState, NewAction, Fabric, Croupier, Amnesia, Opponent, Permission, Type}).
%
new_agent_stuff_val(NewCoins, NewState, NewAction) ->
	[{_, CurCoins, _, _, Fabric, Croupier, Amnesia, Opponent, Permission, Type}] = ets:lookup(list_to_atom(pid_to_list(self())), self()),
	ets:insert(list_to_atom(pid_to_list(self())), {self(), CurCoins+NewCoins, NewState, NewAction, Fabric, Croupier, Amnesia, Opponent, Permission, Type}).
%
increment_number_of_deals() ->
	agents_increase_deals(self()).
%
set_dead() ->
	agents_state_dead(self()).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%[idle, advertizing, negotiating, playing]
%Event = [advert, deal, play, relax].
%StatesMap = #{	idle 		=> [{advert, advertizing}],
%				advertizing => [{relax, idle}, {talk, negotiating}],
%				negotiating => [{relax, idle}, {bet, playing}],
%				playing		=> [{relax, idle}]}.
%
%EventsMap = #{	fabric 		=> [state, start, stop, die],
%				database 	=> [advert_done, got_opponent],
%				croupier	=> [bet_done, game_over],
%				opponent	=> [ready_to_play]}.
%
%AgentStateMap = #{name 		=> self(),
%				 state 		=> idle, 
%				 fabric 	=> Fabric, 
%				 trader 	=> Croupier, 
%				 database 	=> Amnesia,
%				 opponent 	=> no_opponent,
%				 permission => denied}.
%NewAgentStateMap = maps:put(key2, "new value", AgentStateMap).
	
%
%event(Event) ->
%	ActionsList = maps:get(maps:get(state, AgentStateMap), StatesMap),
%	[NeededState] = [State || {CaseAction, State} <- ActionsList, CaseAction =:= Event],
%	case Event of
%		advert	-> send_msg(maps:get(database, AgentStateMap), self(), advert, req);
%		deal	-> send_msg(maps:get(opponent, AgentStateMap), self(), wanna_play, req);
%		play	-> send_msg(maps:get(trader,   AgentStateMap), self(), {1, maps:get(trader,   AgentStateMap)}, req);
%		relax	-> okay
%	end,
%	NewAgentStateMap = maps:put(state, NeededState, AgentStateMap).
	

	
	
	
