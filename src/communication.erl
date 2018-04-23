-module(communication).
-export([send_msg/4]).

send_msg(Destination, Sender, Msg, Type) ->
	case Type of
		%req -> io:format("~p~n", [{ Sender, Destination, Msg, Type}]);
		_ -> ok
	end,	
	Destination ! {Sender, Msg, Type}.
%	io:format("~p~n", [{ Sender, Destination, Msg, Type}]),
%	{Pid, Node} = Destination,
%	FinalNode = atom_to_list(Node),
%	io:format("FinalNode: ~p~n", [FinalNode]),
%	FionalDestination = {Pid, FinalNode},

%	FionalDestination ! {Sender, Msg, Type}.
