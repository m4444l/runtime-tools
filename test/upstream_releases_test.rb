# frozen_string_literal: true
require "minitest/autorun"
require "minitest/mock"
require "tempfile"
require_relative "../lib/runtime_tools/upstream_releases"

class UpstreamReleasesTest < Minitest::Test
  def check(tool, current, page)
    lock = { "tools" => { tool => { "version" => current } } }
    RuntimeTools::UpstreamReleases.check(lock, fetcher: ->(_url) { page }).first
  end

  def test_mupdf_uses_source_archives_and_numeric_order
    result = check("mupdf", "1.9.0", <<~HTML)
      {"File":"mupdf-1.10.0-source.tar.gz"}
      {"File":"mupdf-1.9.0-source.tar.gz"}
      {"File":"mupdf-2.0.0-rc1-source.tar.gz"}
      {"File":"pymupdf-3.0.0-source.tar.gz"}
      {"File":"mupdf-4.0.0-windows.zip"}
    HTML
    assert_equal "1.10.0", result.fetch(:latest)
    assert result.fetch(:newer)
  end

  def test_ffmpeg_ignores_prereleases_and_older_release_branches
    result = check("ffmpeg", "9.0.2", <<~HTML)
      <a href="releases/ffmpeg-8.1.3.tar.xz">Older branch</a>
      <a href="releases/ffmpeg-9.0.2.tar.xz">Stable</a>
      <a href="releases/ffmpeg-10.0-rc1.tar.xz">Prerelease</a>
    HTML
    assert_equal "9.0.2", result.fetch(:latest)
    refute result.fetch(:newer)
  end

  def test_major_and_two_component_releases
    assert check("ffmpeg", "9.0.2", "ffmpeg-10.0.tar.xz").fetch(:newer)
  end

  def test_older_upstream_listing_does_not_request_a_downgrade
    refute check("mupdf", "1.28.4", "mupdf-1.28.3-source.tar.gz").fetch(:newer)
  end

  def test_changed_page_format_fails_instead_of_reporting_up_to_date
    assert_raises(RuntimeError) { check("mupdf", "1.28.4", "<html>No downloads</html>") }
  end

  def test_network_failure_is_not_treated_as_up_to_date
    lock = { "tools" => { "ffmpeg" => { "version" => "9.0.2" } } }
    assert_raises(IOError) do
      RuntimeTools::UpstreamReleases.check(lock, fetcher: ->(_url) { raise IOError, "connection failed" })
    end
  end

  def test_exit_status_and_actions_summary
    previous_summary = ENV["GITHUB_STEP_SUMMARY"]
    Tempfile.create("release-summary") do |file|
      ENV["GITHUB_STEP_SUMMARY"] = file.path
      [false, true].each do |newer|
        result = { newer:, tool: "ffmpeg", current: "9.0.2", latest: "10.0", url: "https://ffmpeg.org/download.html" }
        RuntimeTools::UpstreamReleases.stub(:check, [result]) do
          capture_io { assert_equal(newer ? 1 : 0, RuntimeTools::UpstreamReleases.run) }
        end
      end
      summary = File.read(file.path)
      assert_includes summary, "Update available"
      assert_includes summary, "No newer release"
      assert_includes summary, "9.0.2 | 10.0"
    end
  ensure
    ENV["GITHUB_STEP_SUMMARY"] = previous_summary
  end
end
