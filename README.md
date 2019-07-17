To generate the bindings yourself (you need this if your LLVM version is not 7.x), install [crystal\_lib](https://github.com/crystal-lang/crystal_lib) and run:

```
./tools/gen_binding_descr.sh | crystal_lib > src/lib_llvm_c.cr
```
