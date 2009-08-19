%%% ====================================================================
%%% ``The contents of this file are subject to the Erlang Public License,
%%% Version 1.1, (the "License"); you may not use this file except in
%%% compliance with the License. You should have received a copy of the
%%% Erlang Public License along with this software. If not, it can be
%%% retrieved via the world wide web at http://www.erlang.org/.
%%% 
%%% Software distributed under the License is distributed on an "AS IS"
%%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%%% the License for the specific language governing rights and limitations
%%% under the License.
%%% 
%%% The Initial Developer of the Original Code is ProcessOne.
%%% Portions created by ProcessOne are Copyright 2006-2009, ProcessOne
%%% All Rights Reserved.''
%%% This software is copyright 2006-2009, ProcessOne.
%%%
%%%
%%% @copyright 2006-2009 ProcessOne
%%% @author Christophe Romain <christophe.romain@process-one.net>
%%%   [http://www.process-one.net/]
%%% @version {@vsn}, {@date} {@time}
%%% @end
%%% ====================================================================

%%% @doc The module <strong>{@module}</strong> is the default PubSub node tree plugin.
%%% <p>It is used as a default for all unknown PubSub node type.  It can serve
%%% as a developer basis and reference to build its own custom pubsub node tree
%%% types.</p>
%%% <p>PubSub node tree plugins are using the {@link gen_nodetree} behaviour.</p>
%%% <p><strong>The API isn't stabilized yet</strong>. The pubsub plugin
%%% development is still a work in progress. However, the system is already
%%% useable and useful as is. Please, send us comments, feedback and
%%% improvements.</p>

-module(nodetree_tree_odbc).
-author('christophe.romain@process-one.net').

-include("pubsub.hrl").
-include("jlib.hrl").

-define(PUBSUB, mod_pubsub_odbc).
-define(PLUGIN_PREFIX, "node_").

-behaviour(gen_pubsub_nodetree).

-export([init/3,
	 terminate/2,
	 options/0,
	 set_node/1,
	 get_node/3,
	 get_node/2,
	 get_node/1,
	 get_nodes/2,
	 get_nodes/1,
	 get_parentnodes/3,
	 get_parentnodes_tree/3,
	 get_subnodes/3,
	 get_subnodes_tree/3,
	 create_node/5,
	 delete_node/2
	]).

-export([raw_to_node/2]).

%% ================
%% API definition
%% ================

%% @spec (Host, ServerHost, Opts) -> any()
%%     Host = mod_pubsub:host()
%%     ServerHost = host()
%%     Opts = list()
%% @doc <p>Called during pubsub modules initialisation. Any pubsub plugin must
%% implement this function. It can return anything.</p>
%% <p>This function is mainly used to trigger the setup task necessary for the
%% plugin. It can be used for example by the developer to create the specific
%% module database schema if it does not exists yet.</p>
init(_Host, _ServerHost, _Opts) ->
    ok.
terminate(_Host, _ServerHost) ->
    ok.

%% @spec () -> [Option]
%%     Option = mod_pubsub:nodetreeOption()
%% @doc Returns the default pubsub node tree options.
options() ->
    [{virtual_tree, false},
     {odbc, true}].


get_node(Host, Node, _From) ->
    get_node(Host, Node).

%% @spec (Host, Node) -> pubsubNode() | {error, Reason}
%%     Host = mod_pubsub:host()
%%     Node = mod_pubsub:pubsubNode()
get_node(Host, Node) ->
    H = ?PUBSUB:escape(Host),
    N = ?PUBSUB:escape(?PUBSUB:node_to_string(Node)),
    case catch ejabberd_odbc:sql_query_t(
		 ["select node, parent, type, nodeid "
		  "from pubsub_node "
		  "where host='", H, "' and node='", N, "';"])
	of
	{selected, ["node", "parent", "type", "nodeid"], [RItem]} ->
	    raw_to_node(Host, RItem);
	{'EXIT', _Reason} ->
	    {error, ?ERR_INTERNAL_SERVER_ERROR};
	_ ->
	    {error, ?ERR_ITEM_NOT_FOUND}
    end.
get_node(NodeId) ->
    case catch ejabberd_odbc:sql_query_t(
		 ["select host, node, parent, type "
		  "from pubsub_node "
		  "where nodeid='", NodeId, "';"])
	of
	{selected, ["host", "node", "parent", "type"], [{Host, Node, Parent, Type}]} ->
	    raw_to_node(Host, {Node, Parent, Type, NodeId});
	{'EXIT', _Reason} ->
	    {error, ?ERR_INTERNAL_SERVER_ERROR};
	_ ->
	    {error, ?ERR_ITEM_NOT_FOUND}
    end.

get_nodes(Host, _From) ->
    get_nodes(Host).
%% @spec (Host) -> [pubsubNode()] | {error, Reason}
%%	 Host = mod_pubsub:host() | mod_pubsub:jid()
get_nodes(Host) ->
    H = ?PUBSUB:escape(Host),
    case catch ejabberd_odbc:sql_query_t(
		 ["select node, parent, type, nodeid "
		  "from pubsub_node "
		  "where host='", H, "';"])
	of
	{selected, ["node", "parent", "type", "nodeid"], RItems} ->
	    lists:map(fun(Item) -> raw_to_node(Host, Item) end, RItems);
	_ ->
	    []
    end.

%% @spec (Host, Node, From) -> [{Depth, Record}] | {error, Reason}
%%     Host   = mod_pubsub:host() | mod_pubsub:jid()
%%     Node   = mod_pubsub:pubsubNode()
%%     From   = mod_pubsub:jid()
%%     Depth  = integer()
%%     Record = pubsubNode()
%% @doc <p>Default node tree does not handle parents, return empty list.</p>
get_parentnodes(_Host, _Node, _From) ->
    [].

%% @spec (Host, Node, From) -> [{Depth, Record}] | {error, Reason}
%%     Host   = mod_pubsub:host() | mod_pubsub:jid()
%%     Node   = mod_pubsub:pubsubNode()
%%     From   = mod_pubsub:jid()
%%     Depth  = integer()
%%     Record = pubsubNode()
%% @doc <p>Default node tree does not handle parents, return a list
%% containing just this node.</p>
get_parentnodes_tree(Host, Node, From) ->
    case get_node(Host, Node, From) of
	N when is_record(N, pubsub_node) -> [{0, [N]}];
	Error -> Error
    end.

get_subnodes(Host, Node, _From) ->
    get_subnodes(Host, Node).

%% @spec (Host, Index) -> [pubsubNode()] | {error, Reason}
%%	 Host = mod_pubsub:host()
%%	 Node = mod_pubsub:pubsubNode()
get_subnodes(Host, Node) ->
    H = ?PUBSUB:escape(Host),
    N = ?PUBSUB:escape(?PUBSUB:node_to_string(Node)),
    case catch ejabberd_odbc:sql_query_t(
		 ["select node, parent, type, nodeid "
		  "from pubsub_node "
		  "where host='", H, "' and parent='", N, "';"])
	of
	{selected, ["node", "parent", "type", "nodeid"], RItems} ->
	    lists:map(fun(Item) -> raw_to_node(Host, Item) end, RItems);
	_ ->
	    []
    end.

get_subnodes_tree(Host, Node, _From) ->
    get_subnodes_tree(Host, Node).

%% @spec (Host, Index) -> [pubsubNode()] | {error, Reason}
%%	 Host = mod_pubsub:host()
%%	 Node = mod_pubsub:pubsubNode()
get_subnodes_tree(Host, Node) ->
    H = ?PUBSUB:escape(Host),
    N = ?PUBSUB:escape(?PUBSUB:node_to_string(Node)),
    case catch ejabberd_odbc:sql_query_t(
		["select node, parent, type, nodeid "
		 "from pubsub_node "
		 "where host='", H, "' and node like '", N, "%';"])
	of
	{selected, ["node", "parent", "type", "nodeid"], RItems} ->
	    lists:map(fun(Item) -> raw_to_node(Host, Item) end, RItems);
	_ ->
	    []
    end.

%% @spec (Host, Node, Type, Owner, Options) -> ok | {error, Reason}
%%	 Host = mod_pubsub:host() | mod_pubsub:jid()
%%	 Node = mod_pubsub:pubsubNode()
%%	 NodeType = mod_pubsub:nodeType()
%%	 Owner = mod_pubsub:jid()
%%	 Options = list()
create_node(Host, Node, Type, _Owner, Options) ->
    case nodeid(Host, Node) of
	{error, ?ERR_ITEM_NOT_FOUND} ->
		{ParentNode, ParentExists} = case Host of 
		{_U, _S, _R} ->
		    %% This is special case for PEP handling
		    %% PEP does not uses hierarchy
		    {[], true};
		_ ->
		    case lists:sublist(Node, length(Node) - 1) of
		    [] ->
			{[], true};
		    Parent ->
			case nodeid(Host, Parent) of
			    {result, _} -> {Parent, true};
			    _ -> {Parent, false}
			end
		    end
		end,
	    case ParentExists of
		true -> 
		    case set_node(#pubsub_node{
				nodeid={Host, Node},
				parents=[ParentNode],
				type=Type,
				options=Options}) of
			{result, NodeId} -> {ok, NodeId};
			Other -> Other
		    end;
		false -> 
		    %% Requesting entity is prohibited from creating nodes
		    {error, ?ERR_FORBIDDEN}
	    end;
	{result, _} -> 
	    %% NodeID already exists
	    {error, ?ERR_CONFLICT};
	Error -> 
	    Error
    end.

%% @spec (Host, Node) -> [mod_pubsub:node()]
%%	 Host = mod_pubsub:host() | mod_pubsub:jid()
%%	 Node = mod_pubsub:pubsubNode()
delete_node(Host, Node) ->
    H = ?PUBSUB:escape(Host),
    N = ?PUBSUB:escape(?PUBSUB:node_to_string(Node)),
    Removed = get_subnodes_tree(Host, Node),
    catch ejabberd_odbc:sql_query_t(
	    ["delete from pubsub_node "
	     "where host='", H, "' and node like '", N, "%';"]),
    Removed.

%% helpers

raw_to_node(Host, {Node, Parent, Type, NodeId}) ->
    Options = case catch ejabberd_odbc:sql_query_t(
			   ["select name,val "
			    "from pubsub_node_option "
			    "where nodeid='", NodeId, "';"])
		  of
		  {selected, ["name", "val"], ROptions} ->
		    	DbOpts = lists:map(fun({Key, Value}) -> 
					RKey = list_to_atom(Key),
					Tokens = element(2, erl_scan:string(Value++".")),
					RValue = element(2, erl_parse:parse_term(Tokens)),
					{RKey, RValue}
				end, ROptions),
				Module = list_to_atom(?PLUGIN_PREFIX++Type),
				StdOpts = Module:options(),
				lists:foldl(fun({Key, Value}, Acc)->
					lists:keyreplace(Key, 1, Acc, {Key, Value})
				end, StdOpts, DbOpts);
		  _ ->
		      []
	      end,
    #pubsub_node{
		nodeid = {Host, string_to_node(Host, Node)}, 
		parents = [string_to_node(Host, Parent)],
		id = NodeId,
		type = Type, 
		options = Options}.

%% @spec (NodeRecord) -> ok | {error, Reason}
%%	 Record = mod_pubsub:pubsub_node()
set_node(Record) ->
    {Host, Node} = Record#pubsub_node.nodeid,
    [Parent] = Record#pubsub_node.parents,
    Type = Record#pubsub_node.type,
    H = ?PUBSUB:escape(Host),
    N = ?PUBSUB:escape(?PUBSUB:node_to_string(Node)),
    P = ?PUBSUB:escape(?PUBSUB:node_to_string(Parent)),
    NodeId = case nodeid(Host, Node) of
		 {result, OldNodeId} ->
		     catch ejabberd_odbc:sql_query_t(
			     ["delete from pubsub_node_option "
			      "where nodeid='", OldNodeId, "';"]),
		     catch ejabberd_odbc:sql_query_t(
			     ["update pubsub_node "
			      "set host='", H, "' "
			      "node='", N, "' "
			      "parent='", P, "' "
			      "type='", Type, "' "
			      "where nodeid='", OldNodeId, "';"]),
		     OldNodeId;
		 _ ->
		     catch ejabberd_odbc:sql_query_t(
			     ["insert into pubsub_node(host, node, parent, type) "
			      "values('", H, "', '", N, "', '", P, "', '", Type, "');"]),
		     case nodeid(Host, Node) of
			 {result, NewNodeId} -> NewNodeId;
			 _ -> none  % this should not happen
		     end
	     end,
    case NodeId of
	none ->
	    {error, ?ERR_INTERNAL_SERVER_ERROR};
	_ ->
	    lists:foreach(fun({Key, Value}) ->
				  SKey = atom_to_list(Key),
				  SValue = ?PUBSUB:escape(lists:flatten(io_lib:fwrite("~p",[Value]))),
				  catch ejabberd_odbc:sql_query_t(
					  ["insert into pubsub_node_option(nodeid, name, val) "
					   "values('", NodeId, "', '", SKey, "', '", SValue, "');"]) 
			  end, Record#pubsub_node.options),
	    {result, NodeId}
    end.

nodeid(Host, Node) ->
    H = ?PUBSUB:escape(Host),
    N = ?PUBSUB:escape(?PUBSUB:node_to_string(Node)),
    case catch ejabberd_odbc:sql_query_t(
		 ["select nodeid "
		  "from pubsub_node "
		  "where host='", H, "' and node='", N, "';"])
	of
	{selected, ["nodeid"], [{NodeId}]} ->
	    {result, NodeId};
	{'EXIT', _Reason} ->
	    {error, ?ERR_INTERNAL_SERVER_ERROR};
	_ ->
	    {error, ?ERR_ITEM_NOT_FOUND}
    end.

string_to_node({_, _, _}, Node) -> Node;
string_to_node(_, Node) -> ?PUBSUB:string_to_node(Node).