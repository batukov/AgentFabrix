-module(new_agent).


-record(agent_stuff, {coins = 100, state = idle, fabric = undefined, croupier = undefined, database = undefined, opponent = undefined, permission = denied, type = undefined}).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% RECORDS STUFF
%
set_coins(Rec, Val) ->
	Rec#agent_stuff{coins = Val}.
%
get_coins(Rec) ->
	Rec#agent_stuff.coins.
%%%%%%
set_state(Rec, Val) ->
	Rec#agent_stuff{state = Val}.
%
get_state(Rec) ->
	Rec#agent_stuff.state.
%%%%%%
set_fabric(Rec, Val) ->
	Rec#agent_stuff{fabric = Val}.
%
get_fabric(Rec) ->
	Rec#agent_stuff.fabric.
%%%%%
set_croupier(Rec, Val) ->
	Rec#agent_stuff{croupier = Val}.
%
get_croupier(Rec) ->
	Rec#agent_stuff.croupier.
%%%%%
set_database(Rec, Val) ->
	Rec#agent_stuff{database = Val}.
%
get_database(Rec) ->
	Rec#agent_stuff.database.
%%%%%
set_opponent(Rec, Val) ->
	Rec#agent_stuff{opponent = Val}.
%
get_opponent(Rec) ->
	Rec#agent_stuff.opponent.
%%%%%
set_permission(Rec, Val) ->
	Rec#agent_stuff{permission = Val}.
%
get_permission(Rec) ->
	Rec#agent_stuff.permission.
%%%%%
set_type(Rec, Val) ->
	Rec#agent_stuff{type = Val}.
%
get_type(Rec) ->
	Rec#agent_stuff.type.
%%%%%
create_agent_stuff(Coins, State, Fabric, Croupier, Database, Opponent, Permission, Type) ->
	Rec#agent_stuff{coins = Coins, state = State, fabric = Fabric, croupier = Croupier, database = Database, opponent = Opponent, permission = Permission, type = Type}.
%
get_addresses(Rec) ->
	{Rec#agent_stuff.fabric, Rec#agent_stuff.croupier, Rec#agent_stuff.database, Rec#agent_stuff.opponent}.
%
save_stuff(Rec) ->
	Rec.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
agent_start(Fabric, Croupier, Amnesia, Type) ->
	Rec = create_agent_stuff(100, idle, Fabric, Croupier, Amnesia, self(), denied, Type),
	io:format("am here~n"),
	agent_process(Rec). 
%
agent_process(Rec) ->
	Stuff = call_state(Rec),
	agent_process(Stuff).
%
call_state(Record) ->
	case get_state(Record) of
		idle 		-> idle(Record);
		advertizing -> advertizing(Record);
		negotiating -> negotiating(Record);
		playing 	-> playing(Record);
		wait 		-> wait();
		_ 			-> broken
	end.
%
%[idle, advertizing, negotiating, playing]
%Event = [advert, deal, play, relax].

idle(Record) ->
	{Fabric, Croupier, Amnesia, Opponent} = get_addresses(Record),
	
	send_msg(Amnesia, self(), advert, req),

	receive
		{Fabric, Msg, _} 	->	case Msg of
									state 	-> send_msg (Fabric, self(), Record, sys), save_stuff(Record);
									start 	-> set_state(Record, idle);
									wait	-> set_state(Record, wait);
									stop	-> set_permission(Record, denied);
									die   	-> io:format ("~p is dead ~n", [self()]), exit(self(), kill), save_stuff(Record);
									_ 		-> io:format("unknown message from ~p~n", [Fabric]), save_stuff(Record)
								end;
		{Amnesia, Msg, _} 	-> 	case Msg of
									advert_done	-> set_state(Record, advertizing);
									GotOpponent	-> set_opponent(Record, GotOpponent),
												   set_state(Record, negotiating);
									_			-> io:format("unknown message from ~p~n", [Amnesia]), save_stuff(Record)

								end
	after 2000
		set_state(Record, idle)
	end.
%
advertizing(Record) ->
	{Fabric, Croupier, Amnesia, _} = get_addresses(Record),
	
%	send_msg(Amnesia, self(), advert, req),

	receive
		{Fabric, Msg, _} 	->	case Msg of
									state 	-> send_msg (Fabric, self(), Record, sys), save_stuff(Record);
									start 	-> set_state(Record, idle);
									wait	-> set_state(Record, wait);
									stop	-> set_permission(Record, denied);
									die   	-> io:format ("~p is dead ~n", [self()]), exit(self(), kill), save_stuff(Record);
									_ 		-> io:format("unknown message from ~p~n", [Fabric]), save_stuff(Record)
								end;
		{Amnesia, Msg, _} 	-> 	case Msg of
%									advert_done	-> set_state(Record, advertizing);
									GotOpponent	-> set_opponent(Record, GotOpponent),
												   set_state(Record, negotiating);
									_			-> io:format("unknown message from ~p~n", [Amnesia]), save_stuff(Record)

								end
	after 2000
		set_state(Record, advertizing)
	end.
%
negotiating(Record) ->
	{Fabric, Croupier, Amnesia, Opponent} = get_addresses(Record),
	
	send_msg(Opponent, self(), advert, req),

	receive
		{Fabric, Msg, _} 	->	case Msg of
									state 	-> send_msg (Fabric, self(), Record, sys), save_stuff(Record);
									start 	-> set_state(Record, idle);
									wait	-> set_state(Record, wait);
									stop	-> set_permission(Record, denied);
									die   	-> io:format ("~p is dead ~n", [self()]), exit(self(), kill), save_stuff(Record);
									_ 		-> io:format("unknown message from ~p~n", [Fabric]), save_stuff(Record)
								end;
		{Opponent, Msg, _} 	-> 	case Msg of
									wanna_play -> new_agent_stuff_opp(going_to_deal, get_deal, SomeAgent);
									sure_thing -> new_agent_stuff_opp(deal_done, do_bet, SomeAgent);
%									advert_done	-> set_state(Record, advertizing);
									GotOpponent	-> set_opponent(Record, GotOpponent),
												   set_state(Record, negotiating);
									_			-> io:format("unknown message from ~p~n", [Amnesia]), save_stuff(Record)

								end
	after 2000
		set_state(Record, idle)
	end.










