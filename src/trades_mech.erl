-module(trades_mech).

-export([croupier/0]).
-import(communication, [send_msg/4]).
%
gamble(Gambler1, Val1, Gambler2, Val2) when Val1 < Val2   -> {Gambler1, 3, Gambler2, -1};
gamble(Gambler1, Val1, Gambler2, Val2) when Val2 < Val1   -> {Gambler1, -1, Gambler2, 3};
gamble(Gambler1, Val1, Gambler2, Val2) when Val1 == 0, Val2 == 0 -> {Gambler1, 0, Gambler2, 0};
gamble(Gambler1, Val1, Gambler2, Val2) when Val1 == 1, Val2 == 1 -> {Gambler1, 2, Gambler2, 2}.
%

%
croupier() -> spawn(fun() ->  CroupTable = ets:new(ct_ets, [named_table, set, private, {keypos, 1}]), gambling_thread(CroupTable) end).
%
gambling_thread(CroupTable) ->
	receive
		{Gambler, {Val1, Opponent}, _} when Val1 < 2	-> 	case ets:lookup(ct_ets, Opponent) of
																[{Name, Value}]	-> ets:delete(ct_ets, Opponent),
																			 {Gambler1, Res1, Gambler2, Res2} = gamble(Name, Value, Gambler, Val1),
																			 send_msg(Gambler1, self(), Res1, req), send_msg(Gambler2, self(), Res2, req);
																[] 		-> ets:insert(ct_ets, {Gambler, Val1}), send_msg(Gambler, self(), bet_got, req);
																[_] 		-> ets_failed
															end;
		{Gambler, dead, req}				-> GamblersList = ets:lookup(ct_ets, '_'),
												io:format("~p ~n", [GamblersList]),
												send_caution(GamblersList, Gambler);
		{Fabric, state, sys}				-> send_msg(Fabric, self(), trader_is_fine, sys);
		_ 									->	wrong_msg
	end,	
	gambling_thread(CroupTable).

%
send_caution([], _) -> ok;
send_caution([{Number, Value}|Tail], Gambler) ->
	send_msg(Number, self(), {Gambler, dead}, req),
	send_caution(Tail, Gambler).
