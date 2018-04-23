-module(communication).
-export([send_msg/4]).

send_msg(Destination, Sender, Msg, Type) ->
	case Type of
		%req -> io:format("~p~n", [{ Sender, Destination, Msg, Type}]);
		_ -> ok
	end,	
	Destination ! {Sender, Msg, Type}.
%	Socket = ets:lookup(system_table, socket),
%	SpamPort = ets:lookup(system_table, port_spam),
%	gen_udp:send(Socket, {127,0,0,1}, SpamPort, {Destination, Sender, Msg}).
%	io:format("~p~n", [{ Sender, Destination, Msg, Type}]),
