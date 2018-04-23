#include "erl_nif.h"

static ERL_NIF_TERM calc_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  int a;
  if (!enif_get_int(env, argv[0], &a))
    {
        return enif_make_badarg(env);
    }
  a = a*2;
  return enif_make_int(env, a);
}

static ErlNifFunc export_funcs[] = {
    {"calc", 1, calc_nif}
};

ERL_NIF_INIT(agent, export_funcs, NULL, NULL, NULL, NULL)
