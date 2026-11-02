#include <ruby.h>

/* FastRspec::Native — measured hot paths only. Must match FastRspec::PureRuby byte for byte. */

static VALUE engine(VALUE self) { return rb_str_new_cstr("native"); }

void Init_fast_rspec(void) {
  VALUE mFastRspec = rb_define_module("FastRspec");
  VALUE mNative = rb_define_module_under(mFastRspec, "Native");
  rb_define_module_function(mNative, "engine", engine, 0);
}
