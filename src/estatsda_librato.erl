%% @author Johannes Huning <hi@johanneshuning.com>
%% @copyright 2012 Johannes Huning
%% @doc Librato Metrics adapter, sends metrics to librato.
-module (estatsda_librato).

%% See estatsd.hrl for a complete list of introduced types.
-include ("estatsd.hrl").

%% This is an estatsd adapter.
-behaviour (estatsda_adapter).

% Adapter callbacks.
-export ([
  init/1,
  handle_metrics/2,
  sync_handle_metrics/2
]).

%% @doc Process state: Librato Metrics API username and auth-token.
-record (state, {
  user :: string(),
  token :: string()
}).


% ====================== \/ ESTATSD_ADAPTER CALLBACKS ==========================

%% @doc gen_event callback, builds estatsd_librato's initial state.
init({User, Token}) ->
  State = #state{user = User, token = Token},
  {ok, State}.


%% @doc estatsd_adapter callback, asynchronously calls sync_handle_metrics.
handle_metrics(Metrics, State) ->
  spawn(fun() -> sync_handle_metrics(Metrics, State) end),
  {ok, State}.


%% @doc estatsd_adapter callback, sends a report to send to Librato Metrics.
sync_handle_metrics(Metrics, State) ->
  {ok, send_(render_(Metrics), State)}.

% ====================== /\ ESTATSD_ADAPTER CALLBACKS ==========================


% ====================== \/ HELPER FUNCTIONS ===================================

%% @doc Renders recorded metrics into a message readable by Librato Metrics.
render_({Counters, Timers}) ->
  CountersMessage = render_counters_(Counters),
  TimersMessage = render_timers_(Timers),
  % Mochijson2 JSON struct
  Term = [{gauges, CountersMessage ++ TimersMessage}],
  % Encode the final message
  jiffy:encode(pack_json(Term)).

%% @doc Renders the counter metrics
-spec render_counters_(prepared_counters()) -> JsonStruct::term().
render_counters_(Counters) ->
  lists:map(
    fun({KeyAsBinary, ValuePerSec, _NoIncrements}) ->
      case binary:split(KeyAsBinary, <<"-">>, [global]) of
        % A counter adhering to the group convention;
        % That is, minus ("-") separates group from actual key.
        [Group, Source] -> {struct, [
          {name, Group},
          {source, Source},
          {value, ValuePerSec}
        ]};
        % This is a common counter.
        _ -> {struct, [
          {name, KeyAsBinary},
          {value, ValuePerSec}
        ]}
      end
    end,
    Counters).


%% @doc Renders the timer metrics
-spec render_timers_(prepared_timers()) -> JsonStruct::term().
render_timers_(Timers) ->
  lists:map(
    fun({KeyAsBinary, Durations, Count, Min, Max}) ->
      % Calculate the sum and the sum of all squares.
      {Sum, SumSquares} = lists:foldl(fun(Duration, {SumAcc, SumSquaresAcc}) ->
        {SumAcc + Duration, SumSquaresAcc + (Duration * Duration)}
      end, {0, 0}, Durations),

      % Build Mochijson2 JSON fragment
      case binary:split(KeyAsBinary, <<"-">>, [global]) of
        [Group, Source] ->
          {struct, [
            {name, Group},
            {source, Source},
            {count, Count},
            {sum, Sum},
            {max, Max},
            {min, Min},
            {sum_squares, SumSquares}
          ]};

        _ ->
          {struct, [
            {name, KeyAsBinary},
            {count, Count},
            {sum, Sum},
            {max, Max},
            {min, Min},
            {sum_squares, SumSquares}
          ]}
      end
    end,
    Timers).


%% @doc Sends the given metrics JSON to librato.
-spec send_(Message::string(), State::#state{}) ->
  {error, Reason::term()} | {ok, noreply}.
send_(Message, #state{user = User, token = Token}) ->
  Url = "https://metrics-api.librato.com/v1/metrics.json",

  Headers = [
    {"connection", "keep-alive"},
    {"content-type", "application/json"}
  ],
  Options = [
    {basic_auth, {User, Token}},
    {connect_timeout, 2000}
  ],

  case ibrowse:send_req(Url, Headers, post, Message, Options, 5000) of
    {error, Reason} ->
      error_logger:error_msg("[~s] Delivery failed: '~p'", [?MODULE, Reason]),
      {error, Reason};

    _ -> {ok, noreply}
  end.

% ====================== /\ HELPER FUNCTIONS ===================================

%%%===================================================================
%%% JSON
%%%===================================================================

%% List of tuples, put in a document
pack_json([{_,_}|_] = Doc) ->
	{[pack_json(X) || X <- Doc]};
%% List of lists, put in a list
pack_json([H|T] = Doc) ->
	[pack_json(X) || X <- Doc];
%% Data types
pack_json({K, V} = Pack) ->
	{pack_json(K), pack_json(V)};
pack_json(Other) ->
	Other.
%% Unpacking
unpack_json({K, V}) ->
	{unpack_json(K), unpack_json(V)};
unpack_json({L}) when is_list(L) ->
	[unpack_json(X) || X <- L];
unpack_json(L) when is_list(L) ->
	[unpack_json(X) || X <- L];
unpack_json(Other) ->
	Other.	