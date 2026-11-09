/* Ruby 3.2's ruby/internal/stdbool.h defines bool only when the installed ruby/config.h
   carries HAVE_STDBOOL_H; the 3.2.11 build CI uses has only HAVE__BOOL, so bool/true/false
   stay undefined and every Ruby header fails to compile. Ruby 3.3+ includes <stdbool.h>
   itself — the 3.2 floor must not rely on it. */
#include <stdbool.h>
#include <ruby.h>

/* FastRspec::Native — measured hot paths only. Must match FastRspec::PureRuby byte for byte. */

static VALUE engine(VALUE self) { return rb_str_new_cstr("native"); }

void Init_fast_rspec(void) {
  VALUE mFastRspec = rb_define_module("FastRspec");
  VALUE mNative = rb_define_module_under(mFastRspec, "Native");
  rb_define_module_function(mNative, "engine", engine, 0);
}
