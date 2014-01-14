%% @author Diego Echeverri <diegoeche@gmail.com>
%% @copyright 2012 Diego Echeverri
%% @doc Librato Metrics adapter, sends metrics to librato.
-module (estatsda_stathat).

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
  token :: string()
}).


% ====================== \/ ESTATSD_ADAPTER CALLBACKS ==========================

%% @doc gen_event callback, builds estatsd_librato's initial state.
init({Token}) ->
  State = #state{token = Token},
  {ok, State}.


%% @doc estatsd_adapter callback, asynchronously calls sync_handle_metrics.
handle_metrics(Metrics, State) ->
  spawn(fun() -> sync_handle_metrics(Metrics, State) end),
  {ok, State}.


%% @doc estatsd_adapter callback, sends a report to send to Librato Metrics.
sync_handle_metrics(Metrics, State) ->
  {ok, send_(Metrics, State)}.

% ====================== /\ ESTATSD_ADAPTER CALLBACKS ==========================


% ====================== \/ HELPER FUNCTIONS ===================================

%% @doc Encodes a list of tuples to the form key=value,
encode_params_(Params) ->
  Keys = lists:map(
           fun({Key, Value}) ->
               atom_to_list(Key) ++ "=" ++ http_uri:encode(Value)
           end,
           Params),
  string:join(Keys, "&").

%% @doc Sends the given metrics JSON to StatsHat.
send_({Counters, _Timers}, #state{token = Token}) ->
  Headers = [
    {"connection", "keep-alive"}
  ],
  Options = [
    {connect_timeout, 2000}
  ],
  lists:foreach(
    fun({KeyAsBinary, ValuePerSec, _NoIncrements}) ->
        Params = [{stat, binary_to_list(KeyAsBinary)},
                  {ezkey, Token},
                  {count, estatsd:num2str(ValuePerSec)}
                 ],
        Url = "http://api.stathat.com/ez?" ++ encode_params_(Params),
        spawn(
          fun() ->
              case ibrowse:send_req(Url, Headers, get, "", Options, 5000) of
                {error, Reason} ->
                  error_logger:error_msg("[~s] Delivery failed: '~p'", [?MODULE, Reason]),
                  {error, Reason};
                _ ->
                  {ok, noreply}
              end
          end)
    end,
    Counters),
  {ok, noreply}.

% ====================== /\ HELPER FUNCTIONS ===================================
