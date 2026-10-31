# frozen_string_literal: true

module TmpHelpers
  def with_tmpdir(&)
    Dir.mktmpdir('shop-test', &)
  end

  # Fixed path under the project's tmp/ — what many suites do; needs per-worker isolation when parallel.
  def project_tmp(*parts)
    File.expand_path(File.join('..', '..', 'tmp', *parts), __dir__)
  end
end
