--[[

 Test suite for the Lua/APR binding.

 Author: Peter Odding <peter@peterodding.com>
 Last Change: September 26, 2010
 Homepage: http://peterodding.com/code/lua/apr/
 License: MIT

 This Lua script is just a bunch of assert() calls but if you run it using
 `Shake' it also passes as a decent test suite. On Debian and Ubuntu you can
 install this tool by executing:

   sudo apt-get install shake

 For more information about `Shake' see http://shake.luaforge.net/

--]]

local apr = assert(require 'apr')
local _real_assert_ = _G.assert --> hack around `Shake'.

-- TODO Cleanup and extend the tests for `filepath.c'.
-- TODO Create tests for `io_file.c'.
-- TODO apr.dir(), apr.glob(), apr.stat()!

-- Base64 encoding module (base64.c) {{{1

-- Sample data from http://en.wikipedia.org/wiki/Base64#Examples
local plain = 'Man is distinguished, not only by his reason, but by this singular passion from other animals, which is a lust of the mind, that by a perseverance of delight in the continued and indefatigable generation of knowledge, exceeds the short vehemence of any carnal pleasure.'
local coded = 'TWFuIGlzIGRpc3Rpbmd1aXNoZWQsIG5vdCBvbmx5IGJ5IGhpcyByZWFzb24sIGJ1dCBieSB0aGlzIHNpbmd1bGFyIHBhc3Npb24gZnJvbSBvdGhlciBhbmltYWxzLCB3aGljaCBpcyBhIGx1c3Qgb2YgdGhlIG1pbmQsIHRoYXQgYnkgYSBwZXJzZXZlcmFuY2Ugb2YgZGVsaWdodCBpbiB0aGUgY29udGludWVkIGFuZCBpbmRlZmF0aWdhYmxlIGdlbmVyYXRpb24gb2Yga25vd2xlZGdlLCBleGNlZWRzIHRoZSBzaG9ydCB2ZWhlbWVuY2Ugb2YgYW55IGNhcm5hbCBwbGVhc3VyZS4='

-- Check that Base64 encoding returns the expected result.
assert(apr.base64_encode(plain) == coded)

-- Check that Base64 decoding returns the expected result.
assert(apr.base64_decode(coded) == plain)

-- Cryptography module (crypt.c) {{{1

-- Sample data from http://en.wikipedia.org/wiki/MD5#MD5_hashes
-- and http://en.wikipedia.org/wiki/SHA1#Example_hashes

-- Check that MD5 hashing returns the expected result.
assert(apr.md5 '' == 'd41d8cd98f00b204e9800998ecf8427e')
assert(apr.md5 'The quick brown fox jumps over the lazy dog' == '9e107d9d372bb6826bd81d3542a419d6')
assert(apr.md5 'The quick brown fox jumps over the lazy eog' == 'ffd93f16876049265fbaef4da268dd0e')

pass, salt = 'password', 'salt'
hash = apr.md5_encode(pass, salt)
-- Test that MD5 passwords can be validated.
assert(apr.password_validate(pass, hash))

-- Test that SHA1 hashing returns the expected result.
assert(apr.sha1 'The quick brown fox jumps over the lazy dog' == '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12')
assert(apr.sha1 'The quick brown fox jumps over the lazy cog' == 'de9f2c7fd25e1b3afad3e85a0bd17d9b100db4b3')

-- Environment manipulation module (env.c) {{{1

-- Based on http://svn.apache.org/viewvc/apr/apr/trunk/test/testenv.c?view=markup

local TEST_ENVVAR_NAME = "apr_test_envvar"
local TEST_ENVVAR2_NAME = "apr_test_envvar2"
local TEST_ENVVAR_VALUE = "Just a value that we'll check"

-- Test that environment variables can be set.
assert(apr.env_set(TEST_ENVVAR_NAME, TEST_ENVVAR_VALUE))

-- Test that environment variables can be read.
assert(apr.env_get(TEST_ENVVAR_NAME))
assert(apr.env_get(TEST_ENVVAR_NAME) == TEST_ENVVAR_VALUE)

-- Test that environment variables can be deleted.
assert(apr.env_delete(TEST_ENVVAR_NAME))
assert(not apr.env_get(TEST_ENVVAR_NAME))

-- http://issues.apache.org/bugzilla/show_bug.cgi?id=40764

-- Set empty string and test that status is OK.
assert(apr.env_set(TEST_ENVVAR_NAME, ""))
assert(apr.env_get(TEST_ENVVAR_NAME))
assert(apr.env_get(TEST_ENVVAR_NAME) == "")

-- Delete environment variable and retest.
assert(apr.env_delete(TEST_ENVVAR_NAME))
assert(not apr.env_get(TEST_ENVVAR_NAME))

-- Set second variable and test.
assert(apr.env_set(TEST_ENVVAR2_NAME, TEST_ENVVAR_VALUE))
assert(apr.env_get(TEST_ENVVAR2_NAME))
assert(apr.env_get(TEST_ENVVAR2_NAME) == TEST_ENVVAR_VALUE)

-- Finally, test ENOENT (first variable) followed by second != ENOENT.
assert(not apr.env_get(TEST_ENVVAR_NAME))
assert(apr.env_get(TEST_ENVVAR2_NAME))
assert(apr.env_get(TEST_ENVVAR2_NAME) == TEST_ENVVAR_VALUE)

-- Cleanup.
assert(apr.env_delete(TEST_ENVVAR2_NAME))

-- File path manipulation module (filepath.c) {{{1

-- Based on http://svn.apache.org/viewvc/apr/apr/trunk/test/testpath.c?view=markup.

local PSEP, DSEP
local p = apr.platform_get()
if p == 'WIN32' or p == 'NETWARE' or p == 'OS2' then
	PSEP, DSEP = ';', '\\'
else
	PSEP, DSEP = ':', '/'
end
local PX = ""
local P1 = "first path"
local P2 = "second" .. DSEP .. "path"
local P3 = "th ird" .. DSEP .. "path"
local P4 = "fourth" .. DSEP .. "pa th"
local P5 = "fifthpath"
local parts_in = { P1, P2, P3, PX, P4, P5 }
local path_in = table.concat(parts_in, PSEP)
local parts_out = { P1, P2, P3, P4, P5 }
local path_out = table.concat(parts_out, PSEP)

-- list_split_multi
do
  local pathelts = assert(apr.filepath_list_split(path_in))
  assert(#parts_out == #pathelts)
  for i = 1, #pathelts do assert(parts_out[i] == pathelts[i]) end
end

-- list_split_single
for i = 1, #parts_in do
	local pathelts = assert(apr.filepath_list_split(parts_in[i]))
	if parts_in[i] == '' then
		assert(#pathelts == 0)
	else
	assert(#pathelts == 1)
		assert(parts_in[i] == pathelts[1])
	end
end

-- list_merge_multi
do
  local pathelts = {}
  for i = 1, #parts_in do pathelts[i] = parts_in[i] end
  local liststr = assert(apr.filepath_list_merge(pathelts))
  assert(liststr == path_out)
end

-- list_merge_single
for i = 1, #parts_in do
	local liststr = assert(apr.filepath_list_merge{ parts_in[i] })
	if parts_in[i] == '' then
		assert(liststr == '')
	else
		assert(liststr == parts_in[i])
	end
end

-- Filename matching module (fnmatch.c) {{{1

-- Check that the ?, *, and [] wild cards are supported.
assert(apr.fnmatch('lua_apr.?', 'lua_apr.c'))
assert(apr.fnmatch('lua_apr.?', 'lua_apr.h'))
assert(apr.fnmatch('lua_apr.[ch]', 'lua_apr.h'))
assert(not apr.fnmatch('lua_apr.[ch]', 'lua_apr.l'))
assert(not apr.fnmatch('lua_apr.?', 'lua_apr.cc'))
assert(apr.fnmatch('lua*', 'lua51'))

-- Check that filename matching is case sensitive by default.
assert(not apr.fnmatch('lua*', 'LUA51'))

-- Check that case insensitive filename matching works.
assert(apr.fnmatch('lua*', 'LUA51', true))

-- Check that special characters in filename matching are detected.
assert(not apr.fnmatch_test('lua51'))
assert(apr.fnmatch_test('lua5?'))
assert(apr.fnmatch_test('lua5*'))
assert(apr.fnmatch_test('[lL][uU][aA]'))
assert(not apr.fnmatch_test('+-^#@!%'))

-- Directory manipulation module (io_dir.c) {{{1

local function writable(directory)
  local entry = apr.filepath_merge(directory, 'io_dir_writable_check')
  local handle = io.open(entry, 'w')
  if handle and handle:write 'something' and handle:close() then
    os.remove(entry)
    return true
  end
end

-- Make sure apr.temp_dir_get() returns an existing, writable directory
assert(writable(assert(apr.temp_dir_get())))

-- Create a temporary workspace directory for the following tests
assert(apr.dir_make 'io_dir_tests')

-- Change to the temporary workspace directory
assert(apr.filepath_set 'io_dir_tests')

-- Test dir_make()
assert(apr.dir_make 'foobar')
assert(writable 'foobar')

-- Test dir_remove()
assert(apr.dir_remove 'foobar')
assert(not writable 'foobar')

-- Test dir_make_recursive() and dir_remove_recursive()
assert(apr.dir_make_recursive 'foo/bar/baz')
assert(writable 'foo/bar/baz')
assert(apr.dir_remove_recursive 'foo')
assert(not writable 'foo')

-- Random selection of Unicode from my music library :-)
local nonascii = {
  'Mindless Self Indulgence - Despierta Los Niños',
  'Manu Chao - Próxima Estación; Esperanza',
  'Cassius - Au Rêve',
  '菅野 よう子',
}

for _, name in ipairs(nonascii) do
  assert(apr.dir_make(name))
  -- Using writable() here won't work because the APR API deals with UTF-8
  -- while the Lua API does not, which makes the strings non-equal... :-)
  assert('directory' == assert(apr.stat(name, 'type')))
  assert(apr.dir_remove(name))
  assert('directory' ~= apr.stat(name, 'type'))
end

-- Remove temporary workspace directory
assert(apr.filepath_set '..')
assert(apr.dir_remove 'io_dir_tests')

-- String module (str.c) {{{1

filenames = { 'rfc2086.txt', 'rfc1.txt', 'rfc822.txt' }
table.sort(filenames, apr.strnatcmp)
-- Test natural comparison.
assert(filenames[1] == 'rfc1.txt')
assert(filenames[2] == 'rfc822.txt')
assert(filenames[3] == 'rfc2086.txt')

filenames = { 'RFC2086.txt', 'RFC1.txt', 'rfc822.txt' }
table.sort(filenames, apr.strnatcasecmp)
-- Test case insensitive natural comparison.
assert(filenames[1] == 'RFC1.txt')
assert(filenames[2] == 'rfc822.txt')
assert(filenames[3] == 'RFC2086.txt')

-- Test binary size formatting.
assert(apr.strfsize(1024^1) == '1.0K')
assert(apr.strfsize(1024^2) == '1.0M')
assert(apr.strfsize(1024^3) == '1.0G')

command = [[ program argument1 "argument 2" 'argument 3' argument\ 4 ]]
cmdline = assert(apr.tokenize_to_argv(command))
-- Test command line tokenization.
assert(cmdline[1] == 'program')
assert(cmdline[2] == 'argument1')
assert(cmdline[3] == 'argument 2')
assert(cmdline[4] == 'argument 3')
assert(cmdline[5] == 'argument 4')

-- Time routines (time.c) {{{1

-- TODO Clean up and add some inline documentation because this is a mess!
-- Based on http://svn.apache.org/viewvc/apr/apr/trunk/test/testtime.c?view=markup.

local now = 1032030336186711 / 1000000

-- Check that apr.time_now() more or less matches os.time()
assert(math.abs(os.time() - apr.time_now()) <= 1)

-- test_gmtstr (TODO: APR_ENOTIMPL)

-- test_exp_lt (TODO: APR_ENOTIMPL)
do
  local posix_exp = os.date('*t', now)
  local xt = assert(apr.time_explode(now))
  for k, v in pairs(posix_exp) do assert(v == xt[k]) end
end

-- test_exp_get_gmt (ignores floating point precision because on my laptop
-- "now" equals 1032030336.186711 while "imp" equals 1032037536.186710)
do
  local xt = assert(apr.time_explode(now, false)) -- apr_time_exp_gmt
  local imp = assert(apr.time_implode(xt)) -- apr_time_exp_get
  -- gmtoff depends on who runs the tests!
  assert(math.floor(now + xt.gmtoff) == math.floor(imp))
end

-- test_exp_get_lt
do
  local xt = assert(apr.time_explode(now, true)) -- apr_time_exp_lt
  local imp = assert(apr.time_implode(xt)) -- apr_time_exp_get
  assert(xt.gmtoff == 0)
  assert(math.floor(now) == math.floor(imp))
end

-- test_imp_gmt
do
  local xt = assert(apr.time_explode(now, false)) -- apr_time_exp_gmt
  local imp = assert(apr.time_implode(xt, true)) -- apr_time_exp_gmt_get
  assert(math.floor(now) == math.floor(imp))
end

-- URI parsing module (uri.c) {{{1

local hostinfo = 'scheme://user:pass@host:80'
local pathinfo = '/path/file?query-param=value#fragment'
local input = hostinfo .. pathinfo

-- Parse a URL into a table of components.
parsed = assert(apr.uri_parse(input))

-- Validate the parsed URL fields.
assert(parsed.scheme   == 'scheme')
assert(parsed.user     == 'user')
assert(parsed.password == 'pass')
assert(parsed.hostname == 'host')
assert(parsed.port     == '80')
assert(parsed.hostinfo == 'user:pass@host:80')
assert(parsed.path     == '/path/file')
assert(parsed.query    == 'query-param=value')
assert(parsed.fragment == 'fragment')

-- Check that complete and partial URL `unparsing' works.
assert(apr.uri_unparse(parsed) == input)
assert(apr.uri_unparse(parsed, 'hostinfo') == hostinfo)
assert(apr.uri_unparse(parsed, 'pathinfo') == pathinfo)

-- The following string constant was generated using this PHP code:
--   $t=array();
--   for ($i=0; $i <= 255; $i++) $t[] = chr($i);
--   echo urlencode(join($t));
local uri_encoded = '%00%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F+%21%22%23%24%25%26%27%28%29%2A%2B%2C-.%2F0123456789%3A%3B%3C%3D%3E%3F%40ABCDEFGHIJKLMNOPQRSTUVWXYZ%5B%5C%5D%5E_%60abcdefghijklmnopqrstuvwxyz%7B%7C%7D%7E%7F%80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F%90%91%92%93%94%95%96%97%98%99%9A%9B%9C%9D%9E%9F%A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF%B0%B1%B2%B3%B4%B5%B6%B7%B8%B9%BA%BB%BC%BD%BE%BF%C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF%D0%D1%D2%D3%D4%D5%D6%D7%D8%D9%DA%DB%DC%DD%DE%DF%E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF%F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA%FB%FC%FD%FE%FF'
local chars = {}
for i = 0, 255 do chars[#chars+1] = string.char(i) end
local plain_chars = table.concat(chars)

-- Check that apr.uri_encode() works
assert(apr.uri_encode(plain_chars):lower() == uri_encoded:lower())

-- Check that apr.uri_decode() works
assert(apr.uri_decode(uri_encoded):lower() == plain_chars:lower())

-- TODO Check uri_encode() / uri_decode()

-- User/group identification module (user.c) {{{1

-- First check whether apr.user_get() works or returns an error.
assert(apr.user_get())

-- XXX Shake's version of `assert' doesn't preserve multiple return values :-|
local user, group = _real_assert_(apr.user_get())

-- Get the name of the current user.
assert(user)

-- Get primary group of current user.
assert(group)

local env_user = apr.env_get 'USER'
if env_user then
  -- Match result of apr.user_get() against $USER.
  assert(user == env_user)
end

local env_home = apr.env_get 'HOME'
if env_home then
  -- Match result of apr.user_homepath_get() against $HOME.
  assert(apr.user_homepath_get(user) == env_home)
end

-- Universally unique identifiers (uuid.c) {{{1

-- Check that apr.uuid_get() returns at least 500 KB of unique strings.
local set = {}
assert(pcall(function()
  for i = 1, 32000 do
    uuid = _real_assert_(apr.uuid_get())
    -- Don't use Shake's assert() here so the test count doesn't get inflated.
    _real_assert_(not set[uuid], 'duplicate UUID!')
    set[uuid] = true
  end
end))

-- vim: nowrap