Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :minitest
    with.library :rails
  end
end

# shoulda-context 2.0.0 patches Rails::TestUnitReporter#format_rerun_snippet to call a bare
# `executable`, which Rails 8.1 turned into a class-level accessor: every failing test then
# crashes the reporter with NameError. The usual app-side shim:
if defined?(Rails::TestUnitReporter) && !Rails::TestUnitReporter.method_defined?(:executable, true)
  Rails::TestUnitReporter.class_eval do
    private def executable = self.class.executable
  end
end
