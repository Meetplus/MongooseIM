%%%-------------------------------------------------------------------
%%% File    : service_admin_extra_accounts.erl
%%% Author  : Badlop <badlop@process-one.net>, Piotr Nosek <piotr.nosek@erlang-solutions.com>
%%% Purpose : Contributed administrative functions and commands
%%% Created : 10 Aug 2008 by Badlop <badlop@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2008   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
%%%
%%%-------------------------------------------------------------------

-module(service_admin_extra_accounts).
-author('badlop@process-one.net').

-export([
    commands/0,

    %% Accounts
    set_password/3,
    check_password_hash/4,
    delete_old_users/1,
    delete_old_users_for_domain/2,
    ban_account/3,
    num_active_users/2,
    check_account/2,
    check_password/3]).

-ignore_xref([
    commands/0, set_password/3, check_password_hash/4,
    delete_old_users/1, delete_old_users_for_domain/2,
    ban_account/3, num_active_users/2, check_account/2, check_password/3
]).

-include("mongoose.hrl").
-include("ejabberd_commands.hrl").
-include("jlib.hrl").

%%%
%%% Register commands
%%%

-spec commands() -> [ejabberd_commands:cmd(), ...].
commands() ->
    [
        #ejabberd_commands{name = change_password, tags = [accounts],
                           desc = "Change the password of an account",
                           module = ?MODULE, function = set_password,
                           args = [{user, binary}, {host, binary}, {newpass, binary}],
                           result = {res, restuple}},
        #ejabberd_commands{name = check_password_hash, tags = [accounts],
                           desc = "Check if the password hash is correct",
                           longdesc = "Allowed hash methods: md5, sha.",
                           module = ?MODULE, function = check_password_hash,
                           args = [{user, binary}, {host, binary}, {passwordhash, string},
                                   {hashmethod, string}],
                           result = {res, restuple}},
        #ejabberd_commands{name = delete_old_users, tags = [accounts, purge],
                           desc = "Delete users that didn't log in last days, or that never logged",
                           module = ?MODULE, function = delete_old_users,
                           args = [{days, integer}],
                           result = {res, restuple}},
        #ejabberd_commands{name = delete_old_users_vhost, tags = [accounts, purge],
                           desc = "Delete users that didn't log in last days in vhost,"
                                  " or that never logged",
                           module = ?MODULE, function = delete_old_users_for_domain,
                           args = [{host, binary}, {days, integer}],
                           result = {res, restuple}},
        #ejabberd_commands{name = ban_account, tags = [accounts],
                           desc = "Ban an account: kick sessions and set random password",
                           module = ?MODULE, function = ban_account,
                           args = [{user, binary}, {host, binary}, {reason, binary}],
                           result = {res, restuple}},
        #ejabberd_commands{name = num_active_users, tags = [accounts, stats],
                           desc = "Get number of users active in the last days",
                           module = ?MODULE, function = num_active_users,
                           args = [{host, binary}, {days, integer}],
                           result = {users, integer}},
        #ejabberd_commands{name = check_account, tags = [accounts],
                           desc = "Check if an account exists or not",
                           module = ?MODULE, function = check_account,
                           args = [{user, binary}, {host, binary}],
                           result = {res, restuple}},
        #ejabberd_commands{name = check_password, tags = [accounts],
                           desc = "Check if a password is correct",
                           module = ?MODULE, function = check_password,
                           args = [{user, binary}, {host, binary}, {password, binary}],
                           result = {res, restuple}}
        ].

%%%
%%% Accounts
%%%

-spec set_password(jid:user(), jid:server(), binary()) ->
    {error, string()} | {ok, string()}.
set_password(User, Host, Password) ->
    JID = jid:make(User, Host, <<>>),
    case ejabberd_auth:set_password(JID, Password) of
        ok ->
            {ok, io_lib:format("Password for user ~s successfully changed", [jid:to_binary(JID)])};
        {error, Reason} ->
            {error, Reason}
    end.

-spec check_password(jid:user(), jid:server(), binary()) ->  {Res, string()} when
    Res :: ok | incorrect | user_does_not_exist.
check_password(User, Host, Password) ->
    JID = jid:make(User, Host, <<>>),
    case ejabberd_auth:does_user_exist(JID) of
        true ->
            case ejabberd_auth:check_password(JID, Password) of
                true ->
                    {ok, io_lib:format("Password '~s' for user ~s is correct",
                                       [Password, jid:to_binary(JID)])};
                false ->
                    {incorrect, io_lib:format("Password '~s' for user ~s is incorrect",
                                              [Password, jid:to_binary(JID)])}
            end;
        false ->
            {user_does_not_exist,
            io_lib:format("Password '~s@~s' for user ~s is incorrect because this user does not"
                          " exist", [Password, User, Host])}
    end.

-spec check_account(jid:user(), jid:server()) -> {Res, string()} when
    Res :: ok | user_does_not_exist.
check_account(User, Host) ->
    JID = jid:make(User, Host, <<>>),
    case ejabberd_auth:does_user_exist(JID) of
        true ->
            {ok, io_lib:format("User ~s exists", [jid:to_binary(JID)])};
        false ->
            {user_does_not_exist, io_lib:format("User ~s@~s does not exist", [User, Host])}
    end.


-spec check_password_hash(jid:user(), jid:server(),
                          Hash :: binary(), Method :: string()) ->
    {error, string()} | {ok, string()} | {incorrect, string()}.
check_password_hash(User, Host, PasswordHash, HashMethod) ->
    AccountPass = ejabberd_auth:get_password_s(jid:make(User, Host, <<>>)),
    AccountPassHash = case HashMethod of
        "md5" -> get_md5(AccountPass);
        "sha" -> get_sha(AccountPass);
        _ -> undefined
    end,
    case AccountPassHash of
        undefined ->
            {error, "Hash for password is undefined"};
        PasswordHash ->
            {ok, "Password hash is correct"};
        _->
            {incorrect, "Password hash is incorrect"}
    end.


-spec get_md5(binary()) -> string().
get_md5(AccountPass) ->
    lists:flatten([io_lib:format("~.16B", [X])
                   || X <- binary_to_list(crypto:hash(md5, AccountPass))]).
get_sha(AccountPass) ->
    lists:flatten([io_lib:format("~.16B", [X])
                   || X <- binary_to_list(crypto:hash(sha, AccountPass))]).


-spec num_active_users(jid:server(), integer()) -> non_neg_integer().
num_active_users(Domain, Days) ->
    TimeStamp = erlang:system_time(second),
    TS = TimeStamp - Days * 86400,
    try
        {ok, HostType} = mongoose_domain_api:get_domain_host_type(Domain),
        mod_last:count_active_users(HostType, Domain, TS)
    catch _:_ ->
        0
    end.


-spec delete_old_users(integer()) -> {'ok', string()}.
delete_old_users(Days) ->
    Users = lists:append([delete_and_return_old_users(Domain, Days) ||
                             HostType <- ?ALL_HOST_TYPES,
                             Domain <- mongoose_domain_api:get_domains_by_host_type(HostType)]),
    {ok, format_deleted_users(Users)}.

delete_old_users_for_domain(Domain, Days) ->
    Users = delete_and_return_old_users(Domain, Days),
    {ok, format_deleted_users(Users)}.

delete_and_return_old_users(Domain, Days) ->
    Users = ejabberd_auth:get_vh_registered_users(Domain),
    delete_old_users(Days, Users).

-spec delete_old_users(Days, Users) -> Users when Days :: integer(),
                                                  Users :: [jid:simple_bare_jid()].
delete_old_users(Days, Users) ->
    %% Convert older time
    SecOlder = Days*24*60*60,

    %% Get current time
    TimeStampNow = erlang:system_time(second),

    %% Apply the remove function to every user in the list
    lists:filter(fun(User) ->
                         delete_old_user(User, TimeStampNow, SecOlder)
                 end, Users).

format_deleted_users(Users) ->
    io_lib:format("Deleted ~p users: ~p", [length(Users), Users]).

-spec delete_old_user(User :: jid:simple_bare_jid(),
                      TimeStampNow :: non_neg_integer(),
                      SecOlder :: non_neg_integer()) -> boolean().
delete_old_user({LUser, LServer}, TimeStampNow, SecOlder) ->
    %% Check if the user is logged
    JID = jid:make(LUser, LServer, <<>>),
    case ejabberd_sm:get_user_resources(JID) of
        [] -> delete_old_user_if_nonactive_long_enough(JID, TimeStampNow, SecOlder);
        _ -> false
    end.

-spec delete_old_user_if_nonactive_long_enough(JID :: jid:jid(),
                                               TimeStampNow :: non_neg_integer(),
                                               SecOlder :: non_neg_integer()) -> boolean().
delete_old_user_if_nonactive_long_enough(JID, TimeStampNow, SecOlder) ->
    {LUser, LServer} = jid:to_lus(JID),
    {ok, HostType} = mongoose_domain_api:get_domain_host_type(LServer),
    case mod_last:get_last_info(HostType, LUser, LServer) of
        {ok, TimeStamp, _Status} ->
            %% get his age
            Sec = TimeStampNow - TimeStamp,
            %% If he is younger than SecOlder:
            case Sec < SecOlder of
                true ->
                    %% do nothing
                    false;
                %% older:
                false ->
                    %% remove the user
                    ejabberd_auth:remove_user(JID),
                    true
            end;
        not_found ->
            ejabberd_auth:remove_user(JID),
            true
    end.

-spec ban_account(jid:user(), jid:server(), binary() | string()) ->
    {ok, string()} | {error, string()}.
ban_account(User, Host, ReasonText) ->
    JID = jid:make(User, Host, <<>>),
    Reason = service_admin_extra_sessions:prepare_reason(ReasonText),
    kick_sessions(JID, Reason),
    case set_random_password(JID, Reason) of
        ok ->
            {ok, io_lib:format("User ~s successfully banned with reason: ~s",
                               [jid:to_binary(JID), ReasonText])};
        {error, ErrorReason} ->
            {error, ErrorReason}
    end.

-spec kick_sessions(jid:jid(), binary()) -> [ok].
kick_sessions(JID, Reason) ->
    lists:map(
        fun(Resource) ->
                service_admin_extra_sessions:kick_session(
                  jid:replace_resource(JID, Resource), Reason)
        end,
        ejabberd_sm:get_user_resources(JID)).


-spec set_random_password(JID, Reason) -> Result when
      JID :: jid:jid(),
      Reason :: binary(),
      Result :: 'ok' | {error, any()}.
set_random_password(JID, Reason) ->
    NewPass = build_random_password(Reason),
    ejabberd_auth:set_password(JID, NewPass).


-spec build_random_password(Reason :: binary()) -> binary().
build_random_password(Reason) ->
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:universal_time(),
    Date = list_to_binary(
             lists:flatten(
               io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0wZ",
                             [Year, Month, Day, Hour, Minute, Second]))),
    RandomString = mongoose_bin:gen_from_crypto(),
    <<"BANNED_ACCOUNT--", Date/binary, "--", RandomString/binary, "--", Reason/binary>>.


