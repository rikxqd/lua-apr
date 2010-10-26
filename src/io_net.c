/* Network I/O handling module for the Lua/APR binding.
 *
 * Author: Peter Odding <peter@peterodding.com>
 * Last Change: October 26, 2010
 * Homepage: http://peterodding.com/code/lua/apr/
 * License: MIT
 */

#include "lua_apr.h"
#include <apr_network_io.h>

/* Internal functions {{{1 */

/* Socket object structure declaration. */
typedef struct {
  lua_apr_readbuf input;
  lua_apr_writebuf output;
  apr_pool_t *pool;
  apr_socket_t *handle;
  int family, protocol;
} lua_apr_socket;

/* Forward declaration for type structure defined at bottom of file. */
lua_apr_type lua_apr_socket_type;

/* socket_alloc(L) -- allocate and initialize socket object {{{2 */

static apr_status_t socket_alloc(lua_State *L, int family, int protocol, lua_apr_socket **objptr)
{
  lua_apr_socket *object;
  apr_status_t status;

  object = new_object(L, &lua_apr_socket_type);
  object->family = family;
  object->protocol = protocol;
  status = apr_pool_create(&object->pool, NULL);
  if (status == APR_SUCCESS)
    *objptr = object;

  return status;
}

/* socket_init(L, object) -- initialize socket buffers {{{2 */

static void socket_init(lua_State *L, lua_apr_socket *object)
{
  init_buffers(L, &object->input, &object->output, object->handle, 0,
    (lua_apr_buf_rf) apr_socket_recv,
    (lua_apr_buf_wf) apr_socket_send,
    NULL);
}

/* socket_check(L, i, open) -- get socket object from Lua stack {{{2 */

static lua_apr_socket* socket_check(lua_State *L, int i, int open)
{
  lua_apr_socket *object = check_object(L, i, &lua_apr_socket_type);
  if (open && object->handle == NULL)
    luaL_error(L, "attempt to use a closed socket");
  return object;
}

/* family_check(L, i) -- check for address family on Lua stack {{{2 */

static int family_check(lua_State *L, int i)
{
# if APR_HAVE_IPV6
  const char *options[] = { "inet", "inet6", "unspec", NULL };
  const int values[] = { APR_INET, APR_INET6, APR_UNSPEC };
# else
  const char *options[] = { "inet", "unspec", NULL };
  const int values[] = { APR_INET, APR_UNSPEC };
# endif
  return values[luaL_checkoption(L, i, "inet", options)];
}

/* socket_close_impl(L, socket) -- destroy socket object {{{2 */

static apr_status_t socket_close_impl(lua_State *L, lua_apr_socket *object)
{
  apr_status_t status = APR_SUCCESS;

  if (object->handle != NULL) {
    status = apr_socket_close(object->handle);
    object->handle = NULL;
  }
  if (object->pool != NULL) {
    apr_pool_destroy(object->pool);
    object->pool = NULL;
  }

  return status;
}

/* apr.socket_create([protocol [, family]]) -> socket {{{1
 *
 * Create a network socket. On success the new socket object is returned,
 * otherwise a nil followed by an error message is returned. Valid values for
 * the @protocol argument are:
 *
 *  - `'tcp'` to create a [TCP] [tcp] socket (this is the default)
 *  - `'udp'` to create a [UDP] [udp] socket
 *  
 * These are the valid values for the @family argument:
 *
 *  - `'inet'` to create a socket using the [IPv4] [ipv4] address family
 *  - `'inet6'` to create a socket using the [IPv6] [ipv6] address family
 *  - `'unspec'` to pick the system default type (this is the default)
 *
 * Note that `'inet6'` is only supported when `apr.socket_supports_ipv6` is
 * true.
 *
 * [tcp]: http://en.wikipedia.org/wiki/Transmission_Control_Protocol
 * [udp]: http://en.wikipedia.org/wiki/User_Datagram_Protocol
 * [ipv4]: http://en.wikipedia.org/wiki/IPv4
 * [ipv6]: http://en.wikipedia.org/wiki/IPv6
 */

int lua_apr_socket_create(lua_State *L)
{
  /* Socket types */
  const char *proto_options[] = { "tcp", "udp", NULL };
  const int proto_values[] = { APR_PROTO_TCP, APR_PROTO_UDP };

  lua_apr_socket *object;
  apr_status_t status;
  int family, type, protocol;

  protocol = proto_values[luaL_checkoption(L, 1, "tcp", proto_options)];
  family = family_check(L, 2);
  type = protocol == APR_PROTO_TCP ? SOCK_STREAM : SOCK_DGRAM;

  /* Create and initialize the socket and its associated memory pool. */
  status = socket_alloc(L, family, protocol, &object);
  if (status == APR_SUCCESS)
    status = apr_socket_create(&object->handle, family, type, protocol, object->pool);
  if (status != APR_SUCCESS)
    return push_error_status(L, status);
  socket_init(L, object);

  return 1;
}

/* apr.hostname_get() -> name {{{1
 * 
 * Get the name of the current machine. On success the host name string is
 * returned, otherwise a nil followed by an error message is returned.
 */

int lua_apr_hostname_get(lua_State *L)
{
  char hostname[APRMAXHOSTLEN + 1];
  apr_status_t status;
  apr_pool_t *pool;
  
  pool = to_pool(L);
  status = apr_gethostname(hostname, count(hostname), pool);
  if (status != APR_SUCCESS)
    return push_error_status(L, status);
  lua_pushstring(L, hostname);

  return 1;
}

/* apr.host_to_addr(hostname [, family]) -> ip_address {{{1
 *
 * Resolve a host name to an IP-address. On success the IP-address is returned
 * as a string, otherwise a nil followed by an error message is returned. The
 * optional @family argument is documented under `apr.socket_create()`.
 */

int lua_apr_host_to_addr(lua_State *L)
{
  apr_sockaddr_t *address;
  apr_pool_t *pool;
  const char *host;
  char *ip_address;
  apr_status_t status;
  int family;

  pool = to_pool(L);
  host = luaL_checkstring(L, 1);
  family = family_check(L, 2);
  status = apr_sockaddr_info_get(&address, host, family, SOCK_STREAM, 0, pool);
  if (status == APR_SUCCESS)
    status = apr_sockaddr_ip_get(&ip_address, address);
  if (status != APR_SUCCESS)
    return push_error_status(L, status);
  lua_pushstring(L, ip_address);

  return 1;
}

/* apr.addr_to_host(ip_address [, family]) -> hostname {{{1
 *
 * Look up the host name from an IP-address. On success the host name is
 * returned as a string, otherwise a nil followed by an error message is
 * returned. The optional @family argument is documented under
 * `apr.socket_create()`.
 */

int lua_apr_addr_to_host(lua_State *L)
{
  apr_sockaddr_t *address;
  apr_pool_t *pool;
  const char *ip_address;
  char *host;
  apr_status_t status;
  int family;

  pool = to_pool(L);
  ip_address = luaL_checkstring(L, 1);
  family = family_check(L, 2);
  status = apr_sockaddr_info_get(&address, ip_address, family, SOCK_STREAM, 0, pool);
  if (status == APR_SUCCESS)
    status = apr_getnameinfo(&host, address, 0);
  if (status != APR_SUCCESS)
    return push_error_status(L, status);
  lua_pushstring(L, host);

  return 1;
}

/* socket:connect(host, port) -> status {{{1
 *
 * Issue a connection request to a socket either on the same machine or a
 * different one, as indicated by the @host string and @port number. On success
 * true is returned, otherwise a nil followed by an error message is
 * returned.
 */

static int socket_connect(lua_State *L)
{
  lua_apr_socket *object;
  apr_sockaddr_t *address;
  const char *host;
  apr_port_t port;
  apr_status_t status;

  object = socket_check(L, 1, 1);
  host = luaL_checkstring(L, 2);
  port = luaL_checkinteger(L, 3);
  status = apr_sockaddr_info_get(&address, host, object->family, port, 0, object->pool);
  if (status == APR_SUCCESS)
    status = apr_socket_connect(object->handle, address);

  return push_status(L, status);
}

/* socket:bind(host, port) -> status {{{1
 *
 * Bind the socket to the given @host string and @port number. On success true
 * is returned, otherwise a nil followed by an error message is returned. The
 * special @host value `*` can be used to select the default 'any' address. For
 * example if you want to create a web server you can start with the following:
 *
 *     -- Basic single threaded server
 *     server = assert(apr.socket_create())
 *     assert(server:bind('*', 80))
 *     assert(server:listen(10))
 *     while true do
 *       local client = assert(server:accept())
 *       -- Here you can receive data from the client by calling client:read()
 *       -- and send data to the client by calling client:write()
 *     end
 *
 * This function can fail if you try to bind a port below 1000 without
 * superuser privileges or if another process is already bound to the given
 * port number.
 */

static int socket_bind(lua_State *L)
{
  lua_apr_socket *object;
  apr_sockaddr_t *address;
  const char *host;
  apr_port_t port;
  apr_status_t status;

  object = socket_check(L, 1, 1);
  host = luaL_checkstring(L, 2);
  if (strcmp(host, "*") == 0)
    host = APR_ANYADDR;
  port = luaL_checkinteger(L, 3);
  status = apr_sockaddr_info_get(&address, host, object->family, port, 0, object->pool);
  if (status == APR_SUCCESS)
    status = apr_socket_bind(object->handle, address);

  return push_status(L, status);
}

/* socket:listen(backlog) -> status {{{1
 *
 * To listen for incoming network connections three steps must be performed:
 *
 * 1. First a socket is created with `apr.socket_create()`
 * 2. Next a willingness to accept incoming connections and a queue limit for
 *    incoming connections are specified with `socket:listen()` (this call
 *    doesn't block)
 * 3. Finally `socket:accept()` is called to wait for incoming connections
 *
 * On success true is returned, otherwise a nil followed by an error message is
 * returned. The @backlog argument indicates the number of outstanding
 * connections allowed in the socket's listen queue. If this value is less than
 * zero, the listen queue size is set to zero.
 */

static int socket_listen(lua_State *L)
{
  lua_apr_socket *object;
  apr_status_t status;
  apr_int32_t backlog;

  object = socket_check(L, 1, 1);
  backlog = luaL_checkinteger(L, 2);
  status = apr_socket_listen(object->handle, backlog);

  return push_status(L, status);
}

/* socket:accept() -> client_socket {{{1
 *
 * Accept a connection request on a server socket. On success a socket is
 * returned which forms the connection to the client, otherwise a nil followed
 * by an error message is returned. This function blocks until a client
 * connects.
 */

static int socket_accept(lua_State *L)
{
  lua_apr_socket *server, *client;
  apr_status_t status;

  server = socket_check(L, 1, 1);
  status = socket_alloc(L, server->family, server->protocol, &client);
  if (status == APR_SUCCESS)
    status = apr_socket_accept(&client->handle, server->handle, client->pool);
  socket_init(L, client);
  if (status != APR_SUCCESS)
    return push_error_status(L, status);

  return 1;
}

/* socket:read([format, ...]) -> mixed value, ... {{{1
 *
 * This function implements the interface of Lua's `file:read()` function.
 */

static int socket_read(lua_State *L)
{
  lua_apr_socket *object = socket_check(L, 1, 1);
  return read_buffer(L, &object->input);
}

/* socket:write(value [, ...]) -> status {{{1
 *
 * This function implements the interface of Lua's `file:write()` function.
 */

static int socket_write(lua_State *L)
{
  lua_apr_socket *object = socket_check(L, 1, 1);
  int nresults = write_buffer(L, &object->output);
  apr_status_t status = flush_buffer(L, &object->output, 1);
  if (status != APR_SUCCESS)
    return push_error_status(L, status);
  return nresults;
}

/* socket:lines() -> iterator {{{1
 *
 * This function implements the interface of Lua's `file:lines()` function.
 */

static int socket_lines(lua_State *L)
{
  lua_apr_socket *object = socket_check(L, 1, 1);
  return read_lines(L, &object->input);
}

/* socket:timeout_get() -> timeout {{{1
 *
 * Get the timeout value or blocking state of @socket. On success the timeout
 * value is returned, otherwise a nil followed by an error message is returned.
 *
 * The @timeout true means wait forever, false means don't wait at all and a
 * number is the microseconds to wait.
 */

static int socket_timeout_get(lua_State *L)
{
  lua_apr_socket *object;
  apr_status_t status;
  apr_interval_time_t timeout;

  object = socket_check(L, 1, 1);
  status = apr_socket_timeout_get(object->handle, &timeout);
  if (status != APR_SUCCESS)
    return push_error_status(L, status);
  else if (timeout <= 0)
    lua_pushboolean(L, timeout != 0);
  else
    lua_pushinteger(L, (lua_Integer) timeout);

  return 1;
}

/* socket:timeout_set(timeout) -> status {{{1
 *
 * Set the timeout value or blocking state of @socket. On success true is
 * returned, otherwise a nil followed by an error message is returned.
 *
 * The @timeout true means wait forever, false means don't wait at all and a
 * number is the microseconds to wait.
 */

static int socket_timeout_set(lua_State *L)
{
  lua_apr_socket *object;
  apr_status_t status;
  apr_interval_time_t timeout;

  object = socket_check(L, 1, 1);
  if (lua_isnumber(L, 2))
    timeout = luaL_checkinteger(L, 2);
  else
    timeout = lua_toboolean(L, 2) ? -1 : 0;
  status = apr_socket_timeout_set(object->handle, timeout);

  return push_status(L, status);
}

/* socket:addr_get([type]) -> ip_address [, hostname] {{{1
 *
 * Get one of the addresses associated with @socket, according to @type:
 *
 *  - `'local'` to get the address to which the socket is bound locally
 *  - `'remote'` to get the address of the peer to which the socket is connected (this is the default)
 *
 * On success the local or remote IP-address is returned as a string, otherwise
 * a nil followed by an error message is returned. If a host name is available
 * that will be returned as the second value.
 */

static int socket_addr_get(lua_State *L)
{
  const char *options[] = { "local", "remote", NULL };
  const apr_interface_e values[] = { APR_LOCAL, APR_REMOTE };
  lua_apr_socket *object;
  apr_sockaddr_t *address;
  apr_status_t status;
  apr_interface_e which;
  char *ip_address;

  object = socket_check(L, 1, 1);
  which = values[luaL_checkoption(L, 2, "remote", options)];
  status = apr_socket_addr_get(&address, which, object->handle);
  if (status == APR_SUCCESS)
    status = apr_sockaddr_ip_get(&ip_address, address);
  if (status != APR_SUCCESS)
    return push_error_status(L, status);
  lua_pushstring(L, ip_address);
  lua_pushstring(L, address->hostname);

  return 2;
}

/* socket:close() -> status {{{1
 *
 * Close @socket. On success true is returned, otherwise a nil followed by an
 * error message is returned.
 */

static int socket_close(lua_State *L)
{
  return push_status(L, socket_close_impl(L, socket_check(L, 1, 1)));
}

/* socket:__tostring() {{{1 */

static int socket_tostring(lua_State *L)
{
  lua_apr_socket *socket;

  socket = socket_check(L, 1, 0);
  lua_pushfstring(L, "%s Lua/APR socket object",
      socket->handle != NULL ? "Open" : "Closed");

  return 1;
}

/* socket:__gc() {{{1 */

static int socket_gc(lua_State *L)
{
  socket_close_impl(L, socket_check(L, 1, 0));
  return 0;
}

/* }}} */

luaL_reg socket_methods[] = {
  { "bind", socket_bind },
  { "listen", socket_listen },
  { "accept", socket_accept },
  { "connect", socket_connect },
  { "read", socket_read },
  { "write", socket_write },
  { "lines", socket_lines },
  { "timeout_get", socket_timeout_get },
  { "timeout_set", socket_timeout_set },
  { "addr_get", socket_addr_get },
  { "close", socket_close },
  { NULL, NULL },
};

luaL_reg socket_metamethods[] = {
  { "__tostring", socket_tostring },
  { "__gc", socket_gc },
  { NULL, NULL },
};

lua_apr_type lua_apr_socket_type = {
  "lua_apr_socket*",
  sizeof(lua_apr_socket),
  socket_methods,
  socket_metamethods
};
