#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "shellwords"
require "tmpdir"

SCRIPT = File.expand_path("preflight.rb", __dir__)
MODELS = %w[gpt-6-astra gpt-6.1-sol].freeze
CONTEXT_WINDOW = 922_000
AUTO_COMPACT_TOKEN_LIMIT = 700_000
DEFAULT_CONTEXT_WINDOW = 500_000
DEFAULT_AUTO_COMPACT_TOKEN_LIMIT = 400_000
LARGE_PROFILE = <<~TOML
  model_provider = "openai_api_direct"
  model_context_window = 922000
  model_auto_compact_token_limit = 700000
  model_auto_compact_token_limit_scope = "total"
TOML
PROFILES = {
  "astra" => "model = \"gpt-6-astra\"\nmodel_provider = \"openai_api_direct\"\n",
  "sol61" => "model = \"gpt-6.1-sol\"\nmodel_provider = \"openai_api_direct\"\n",
  "astra-1m" => "model = \"gpt-6-astra\"\n#{LARGE_PROFILE}",
  "sol61-1m" => "model = \"gpt-6.1-sol\"\n#{LARGE_PROFILE}",
}.freeze
OUTPUT_SENTINEL = "fixture-output-must-not-appear"

def assert(condition, message)
  raise message unless condition
end

def write_fixture(
  root,
  helper_body:,
  config_overrides: {},
  catalog_overrides: {},
  catalog_models: MODELS,
  profiles: PROFILES
)
  helper = File.join(root, "fetch-key")
  catalog = File.join(root, "models.json")
  config = File.join(root, "config.toml")

  File.write(helper, "#!/bin/sh\nset -eu\n#{helper_body}\n")
  FileUtils.chmod(0o700, helper)
  File.write(
    catalog,
    JSON.generate(
      "models" => catalog_models.map do |slug|
        {
          "slug" => slug,
          "context_window" => CONTEXT_WINDOW,
          "max_context_window" => CONTEXT_WINDOW,
          "auto_compact_token_limit" => AUTO_COMPACT_TOKEN_LIMIT,
        }.merge(catalog_overrides)
      end,
    ),
  )

  root_values = {
    "model" => '"gpt-6-astra"',
    "model_provider" => '"openai_api_direct"',
    "model_context_window" => DEFAULT_CONTEXT_WINDOW,
    "model_auto_compact_token_limit" => DEFAULT_AUTO_COMPACT_TOKEN_LIMIT,
    "model_auto_compact_token_limit_scope" => '"total"',
    "model_catalog_json" => catalog.inspect,
  }.merge(config_overrides)
  root_config = root_values.map { |key, value| "#{key} = #{value}" }.join("\n")

  File.write(
    config,
    <<~TOML,
      #{root_config}

      [model_providers.openai_api_direct]
      name = "OpenAI API direct"
      base_url = "https://api.openai.com/v1"
      wire_api = "responses"
      requires_openai_auth = false

      [model_providers.openai_api_direct.auth]
      command = #{helper.inspect}
      timeout_ms = 5000
      refresh_interval_ms = 300000
    TOML
  )

  profiles.each { |name, body| File.write(File.join(root, "#{name}.config.toml"), body) }
  config
end

def run_preflight(config, *arguments)
  Open3.capture3({ "GITHUB_PAT_TOKEN" => nil }, RbConfig.ruby, SCRIPT, "--config", config, *arguments)
end

MODELS.each do |model|
  Dir.mktmpdir("codex-huge-context-test") do |root|
    config = write_fixture(
      root,
      helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
      config_overrides: { "model" => model.inspect },
    )
    stdout, stderr, process_status = run_preflight(config)
    assert(process_status.success?, "valid #{model} fixture failed: #{stderr}")
    assert(stdout.include?("safe-context preflight: ok"), "success message missing")
    assert(stderr.include?("GITHUB_PAT_TOKEN is unset"), "independent GitHub MCP warning missing")
    assert(!"#{stdout}\n#{stderr}".include?(OUTPUT_SENTINEL), "credential leaked on successful preflight")
  end
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(
    root,
    helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
    config_overrides: { "model_provider" => '"openai"' },
  )
  stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "unsafe provider/context split unexpectedly passed")
  assert(stderr.include?("unsafe split configuration"), "provider/context split failure is unclear")
  assert(stderr.include?("restart every Codex app server"), "provider/context split omits restart recovery")
  assert(stderr.include?("fresh thread"), "provider/context split omits thread recovery")
  assert(!"#{stdout}\n#{stderr}".include?(OUTPUT_SENTINEL), "credential leaked on split-config failure")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(
    root,
    helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'; printf '%s\n' '#{OUTPUT_SENTINEL}' >&2; exit 44",
  )
  stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "failed helper unexpectedly passed")
  assert(stderr.include?("install or repair the dedicated Keychain delivery copy"), "helper failure is not actionable")
  assert(!"#{stdout}\n#{stderr}".include?(OUTPUT_SENTINEL), "credential leaked on failed preflight")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(root, helper_body: "exit 0")
  _stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "empty helper output unexpectedly passed")
  assert(stderr.include?("auth helper returned no credential"), "empty helper failure is unclear")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(
    root,
    helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
    config_overrides: { "model_context_window" => 1_050_000 },
  )
  _stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "unsafe raw context window unexpectedly passed")
  assert(stderr.include?("model_context_window must be 500000"), "context-window failure is unclear")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(
    root,
    helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
    config_overrides: { "model_auto_compact_token_limit" => 945_000 },
  )
  _stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "unsafe compaction threshold unexpectedly passed")
  assert(stderr.include?("model_auto_compact_token_limit must be 400000"), "compaction failure is unclear")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(
    root,
    helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
    config_overrides: { "model_auto_compact_token_limit_scope" => '"body_after_prefix"' },
  )
  _stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "unsafe compaction scope unexpectedly passed")
  assert(stderr.include?("model_auto_compact_token_limit_scope must be \"total\""), "scope failure is unclear")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(
    root,
    helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
    catalog_overrides: { "auto_compact_token_limit" => 900_000 },
  )
  _stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "unsafe catalogue threshold unexpectedly passed")
  assert(stderr.include?("gpt-6-astra.auto_compact_token_limit must be 700000"), "catalogue failure is unclear")
end

[100, nil, 95.0].each do |unsafe_percent|
  Dir.mktmpdir("codex-huge-context-test") do |root|
    config = write_fixture(
      root,
      helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
      catalog_overrides: { "effective_context_window_percent" => unsafe_percent },
    )
    _stdout, stderr, process_status = run_preflight(config)
    assert(!process_status.success?, "unsafe effective-window percentage unexpectedly passed: #{unsafe_percent.inspect}")
    assert(
      stderr.include?("gpt-6-astra.effective_context_window_percent must be omitted or integer 95"),
      "effective-window failure is unclear",
    )
  end
end

MODELS.each do |missing_model|
  Dir.mktmpdir("codex-huge-context-test") do |root|
    config = write_fixture(
      root,
      helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
      catalog_models: MODELS - [missing_model],
    )
    _stdout, stderr, process_status = run_preflight(config)
    assert(!process_status.success?, "catalogue missing #{missing_model} unexpectedly passed")
    assert(stderr.include?("model catalogue is missing #{missing_model}"), "catalogue failure is unclear")
  end
end

PROFILE_FAILURES = {
  "missing sol61-1m" => [PROFILES.reject { |name, _| name == "sol61-1m" }, "profile missing"],
  "1m profile on another provider" => [
    PROFILES.merge("astra-1m" => PROFILES["astra-1m"].sub("openai_api_direct", "openai")),
    "astra-1m profile model_provider must be \"openai_api_direct\"",
  ],
  "mixed context pair" => [
    PROFILES.merge("work" => "model_provider = \"openai_api_direct\"\nmodel_context_window = 922000\n" \
                             "model_auto_compact_token_limit = 400000\n"),
    "work profile must set context/compaction",
  ],
  "wrong profile model" => [PROFILES.merge("sol61" => "model = \"gpt-6-astra\"\n"), "sol61 profile model"],
  "extra profile on the ChatGPT route" => [
    PROFILES.merge("chat" => "model = \"gpt-6.1-sol\"\nmodel_provider = \"openai\"\n"),
    "chat profile selects the ChatGPT-backed",
  ],
  "contract profile on another provider" => [
    PROFILES.merge("astra" => "model = \"gpt-6-astra\"\nmodel_provider = \"other-route\"\n"),
    "astra profile model_provider must be \"openai_api_direct\"",
  ],
}.freeze

PROFILE_FAILURES.each do |label, (profiles, message)|
  Dir.mktmpdir("codex-huge-context-test") do |root|
    config = write_fixture(root, helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'", profiles: profiles)
    _stdout, stderr, process_status = run_preflight(config)
    assert(!process_status.success?, "#{label} unexpectedly passed")
    assert(stderr.include?(message), "#{label} failure is unclear: #{stderr}")
  end
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(
    root,
    helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
    profiles: PROFILES.merge("ultrafast" => "model = \"gpt-6-astra\"\nservice_tier = \"ultrafast\"\n"),
  )
  _stdout, stderr, process_status = run_preflight(config)
  assert(process_status.success?, "profile without context keys failed: #{stderr}")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(
    root,
    helper_body: "printf '%s\n' '#{OUTPUT_SENTINEL}'",
    profiles: PROFILES.merge("router" => "model = \"other\"\nmodel_provider = \"claude-code-router\"\n"),
  )
  _stdout, stderr, process_status = run_preflight(config)
  assert(process_status.success?, "foreign-provider profile should warn, not fail: #{stderr}")
  assert(stderr.include?("router profile switches to"), "inherited-limit warning missing")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  parent_home = ENV.fetch("HOME")
  config = write_fixture(
    root,
    helper_body: <<~SH,
      printf '%s\\n' '#{OUTPUT_SENTINEL}'
      if [ "$HOME" != #{Shellwords.escape(parent_home)} ]; then
        printf '%s\\n' '#{OUTPUT_SENTINEL}' >&2
        exit 44
      fi
    SH
  )
  _stdout, _stderr, process_status = run_preflight(config)
  assert(process_status.success?, "parent-only delivery fixture failed")
  stdout, stderr, process_status = run_preflight(config, "--private-home")
  assert(!process_status.success?, "HOME-dependent helper unexpectedly passed private-home check")
  assert(stderr.include?("private-home auth check failed"), "context mismatch diagnostic missing")
  assert(stderr.include?("explicit Keychain path"), "context mismatch repair guidance missing")
  assert(!"#{stdout}\n#{stderr}".include?(OUTPUT_SENTINEL), "credential leaked on context mismatch")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  calls = File.join(root, "helper-homes")
  parent_home = ENV.fetch("HOME")
  config = write_fixture(
    root,
    helper_body: <<~SH,
      printf '%s\\n' "$HOME" >> #{Shellwords.escape(calls)}
      if [ "$HOME" != #{Shellwords.escape(parent_home)} ]; then
        test "$USERPROFILE" = "$HOME"
        test "$XDG_CONFIG_HOME" = "$HOME/.config"
        test "$XDG_DATA_HOME" = "$HOME/.local/share"
        test "$XDG_STATE_HOME" = "$HOME/.local/state"
        test "$XDG_CACHE_HOME" = "$HOME/.cache"
        for directory in "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"; do
          test -d "$directory"
        done
      fi
      printf '%s\\n' '#{OUTPUT_SENTINEL}'
    SH
  )
  stdout, stderr, process_status = run_preflight(config, "--private-home")
  assert(process_status.success?, "private-home delivery fixture failed: #{stderr}")
  homes = File.readlines(calls, chomp: true)
  assert(homes.length == 2 && homes.first == parent_home, "parent and private checks did not both run")
  assert(homes.last != parent_home, "private-home check reused parent HOME")
  assert(!File.exist?(homes.last), "private-home directories were not cleaned up")
  assert(ENV.fetch("HOME") == parent_home, "preflight changed parent HOME")
  assert(stdout.include?("private-home auth check: ok"), "private-home success message missing")
  assert(!"#{stdout}\n#{stderr}".include?(OUTPUT_SENTINEL), "credential leaked on private-home success")
end

puts "codex huge-context preflight tests passed"
