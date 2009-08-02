#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"

static lua_State *L_VM = NULL;
static int dispatch_table = LUA_REFNIL;

static int l_fdatasync(lua_State *L_VM)
{
    int res = lua_tointeger(L_VM, 1);
    fdatasync(res);
    return 1;
}

static int l_fsync(lua_State *L_VM)
{
    int res = lua_tointeger(L_VM, 1);
    fsync(res);
    return 1;
}

static const luaL_reg fsync_ops[] = {
    { "fdatasync" , l_fdatasync  }, 
    { "fsync"     , l_fsync      }, 
    { NULL        , NULL         }
};

LUA_API int luaopen_fsync(lua_State *L)
{
    luaL_openlib( L, "fsync", fsync_ops, 0 );

    lua_pushliteral (L, "_COPYRIGHT");
    lua_pushliteral (L, "Copyright (C) 2009 Tim Aerts <aardbeiplantje@gmail.com>");
    lua_settable (L, -3);
    lua_pushliteral (L, "_DESCRIPTION");
    lua_pushliteral (L, "Binding to fsync and fdatasync");
    lua_settable (L, -3);
    lua_pushliteral (L, "_VERSION");
    lua_pushliteral (L, "LuaFSYNC 0.1");
    lua_settable (L, -3);

    return 1;
}
