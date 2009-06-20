#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/acl.h>

#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"


static lua_State *L_VM = NULL;
static int dispatch_table = LUA_REFNIL;

static int l_acl_equiv_mode(lua_State *L)
{
    int res = 0;

    //const char *s = lua_tostring(L, 2);
    //fprintf(stderr, "from:%s\n",s);

    acl_t   acl = lua_touserdata(L, 1);
    //acl_t   acl = acl_from_text(s);
    fprintf(stderr, "%s\n", acl_to_text(acl, NULL));
    mode_t  mode;

    res = acl_valid(acl);
    fprintf(stderr, "string:%d\n",res);
    res = acl_check(acl, NULL);
    fprintf(stderr, "string:%d\n",res);

    res = acl_equiv_mode(acl, &mode);
    fprintf(stderr, "string:%d\n",res);

    if(res == 0){
        /* all is well: valid ACL to mode is possible */
        fprintf(stderr, "converted\n");
        lua_pushlightuserdata(L, (void *)&mode);
    } else {
        /* problem */
        fprintf(stderr, "problem\n");
        return 0;
    }

    return 1;
}

static int l_acl_from_text(lua_State *L)
{
    acl_t acl;
    const char *a = lua_tostring(L, 1);
    
    fprintf(stderr, "got:\n%s\n", a);

    acl = acl_from_text(a);
    if (acl == NULL) {
        return 0;
    }

    //size_t s;
    //fprintf(stderr, "%s\n", acl_to_text(acl, &s));
    lua_pushstring(L, (void *)acl);
    //lua_pushstring(L, acl_to_text(acl, NULL));

    return 1;
}


static int l_acl_to_text(lua_State *L)
{
    acl_t acl = lua_touserdata(L, 1);
    
    const char *s = acl_to_text(acl, NULL);
    if (s == NULL) {
        return 0;
    }

    fprintf(stderr, "aa:%s\n", s);
    lua_pushstring(L, s);

    return 1;
}


static const luaL_reg Acl[] = {
    { "acl_equiv_mode" , l_acl_equiv_mode  }, 
    { "acl_from_text"  , l_acl_from_text   }, 
    { "acl_to_text"    , l_acl_to_text     }, 
    { NULL             , NULL              }
};

LUA_API int luaopen_acl(lua_State *L)
{
    luaL_openlib( L, "acl", Acl, 0 );

    lua_pushliteral (L, "_COPYRIGHT");
    lua_pushliteral (L, "Copyright (C) 2009 Tim Aerts <aardbeiplantje@gmail.com>");
    lua_settable (L, -3);
    lua_pushliteral (L, "_DESCRIPTION");
    lua_pushliteral (L, "Binding to libacl");
    lua_settable (L, -3);
    lua_pushliteral (L, "_VERSION");
    lua_pushliteral (L, "LuaACL 0.1");
    lua_settable (L, -3);

    return 1;
}
