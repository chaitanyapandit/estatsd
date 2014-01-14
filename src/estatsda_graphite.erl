%% @author Richard Jones <rj@metabrew.com>
%% @author Johannes Huning <hi@johanneshuning.com>
%% @copyright 2011 Richard Jones
%% @doc Sends received metrics to Graphite.
-module (estatsda_graphite).

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

%% @doc Process state: Graphite instance's hostname and port.
-record (state, {
  host :: string(),
  port :: non_neg_integer()
}).


% ====================== \/ ESTATSD_ADAPTER CALLBACKS ==========================

%% @doc Builds the initial state.
init({Host, Port}) -> {ok, #state{host = Host, port = Port}}.


%% @doc Asynchronously sends the metrics to Graphite.
handle_metrics(Metrics, State) ->
  spawn(fun() -> sync_handle_metrics(Metrics, State) end),
  {ok, State}.


%% @doc estatsd_adapter callback, Sends the recorded metrics to Graphite.
sync_handle_metrics(Metrics, State) ->
  {ok, State, send_(render_(Metrics), State)}.

% ====================== /\ ESTATSD_ADAPTER CALLBACKS ==========================


% ====================== \/ HELPER FUNCTIONS ===================================

%% @doc Renders recorded metrics into a message readable by Graphite.
render_({Counters, Timers}) ->
  % One timestamp used in all stats lines
  Timestamp = estatsd:num2str(estatsd:unixtime()),
  CounterMessage = render_counters_(Counters, Timestamp),
  TimersMessage = render_timers_(Timers, Timestamp),
  % Final message send to Graphite
  [CounterMessage, TimersMessage].


%% @doc Sends the rendered message to Graphite.
send_(Message, #state{host = Host, port = Port}) ->
  case gen_tcp:connect(Host, Port, [list, {packet, 0}]) of
    {ok, Socket} ->
      gen_tcp:send(Socket, Message),
      gen_tcp:close(Socket),
      ok;
    Error ->
      error_logger:error_msg("[~s] Delivery failed: '~p'", [?MODULE, Error]),
      Error
  end.


%% @doc Renders the counter metrics into a message readable by Graphite.
-spec render_counters_(Counters::prepared_counters(),
  Timestamp::non_neg_integer()) -> CountersStringFragment::string().
render_counters_(Counters, Timestamp) ->
  lists:foldl(
    fun({KeyAsBinary, ValuePerSec, NoIncrements}, Acc) ->
      KeyAsString = estatsd:key2str(KeyAsBinary),
      % Build stats string fragment for Graphite
      Fragment = [
        "stats.", KeyAsString, " ",
          estatsd:num2str(ValuePerSec), " ", Timestamp, "\n",
        "stats_counts.", KeyAsString, " ",
          estatsd:num2str(NoIncrements), " ", Timestamp, "\n"
      ],
      % Fold step
      [Fragment | Acc]
    end,
    [], Counters).


%% @doc Renders the timer metrics into a message readable by Graphite.
-spec render_timers_(Timers::prepared_timers(), Timestamp::non_neg_integer()) ->
  TimersStringFragment::string().
render_timers_(Timers, Timestamp) ->
  lists:foldl(
    fun({KeyAsBinary, Durations, Count, Min, Max}, Acc) ->
      KeyAsString = estatsd:key2str(KeyAsBinary),

      UpperThreshold = 90, % In percent
      NumUpperValues  = erlang:round(((100 - UpperThreshold) / 100) * Count),
      NumLowerValues  = Count - NumUpperValues,

      LowerDurations = lists:sublist(Durations, NumLowerValues),
      LowerMax = lists:nth(NumLowerValues, Durations),
      Mean = lists:sum(LowerDurations) / NumLowerValues,

      Prefix = ["stats.timers.", KeyAsString, "."],
      Postfix = [" ", Timestamp, "\n"],

      % Build stats string fragment for Graphite
      Fragment = [lists:map(
        fun({Name, Value}) ->
          [Prefix, Name, " ", estatsd:num2str(Value), Postfix]
        end,
        % Wrap every entry with prefix and postfix
        [
          {"mean", Mean},
          {"upper", Max},
          {"upper_" ++ estatsd:num2str(UpperThreshold), LowerMax},
          {"lower", Min},
          {"count", Count}
        ]
      )],
      % Fold step
      [Fragment | Acc]
  end,
  [], Timers).

% ====================== /\ HELPER FUNCTIONS ===================================
